"""Actual owner configuration captures, Xcode reads, and real loopback HTTP."""
import asyncio
import copy
import hashlib
import http.client
import importlib.util
import json
import os
import plistlib
import shutil
import threading
import time
import unittest
from pathlib import Path

from aiohttp import web

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("mas_config", TOOLS / "verify_mas_purchase_config.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
FIXTURES = Path(__file__).parent / "evidence"


class ConfigurationCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        receipt = json.loads((FIXTURES / "capture.json").read_text())
        cls.raw = {}
        for name, digest in receipt["body_sha256"].items():
            raw = (FIXTURES / name).read_bytes()
            if hashlib.sha256(raw).hexdigest() != digest:
                raise AssertionError("Actual provider capture hash changed")
            cls.raw[name] = raw
        cls.mapping = gate.decode_json(cls.raw["mapping.json"])
        cls.offerings = gate.decode_json(cls.raw["offerings.json"])

    def assert_blocked(self, mapping=None, offerings=None):
        with self.assertRaises(gate.ConfigurationError):
            gate.validate_live_configuration(mapping if mapping is not None else self.mapping,
                                             offerings if offerings is not None else self.offerings)

    def test_actual_sonance_configuration(self):
        result = gate.validate_live_configuration(self.mapping, self.offerings)
        self.assertEqual(result, {"offering": "default", "package": "lifetime",
                                  "product": gate.PRODUCT, "entitlement": "pro"})

    def test_product_missing_or_wrong_identity(self):
        for change in ("missing", "wrong"):
            with self.subTest(change=change):
                mapping = copy.deepcopy(self.mapping)
                if change == "missing":
                    del mapping["product_entitlement_mapping"][gate.PRODUCT]
                else:
                    mapping["product_entitlement_mapping"][gate.PRODUCT]["product_identifier"] += ".other"
                self.assert_blocked(mapping=mapping)

    def test_entitlement_missing_or_ambiguous(self):
        for entitlements in ([], ["other"], ["pro", "pro"], "pro", ["pro", None]):
            with self.subTest(entitlements=entitlements):
                mapping = copy.deepcopy(self.mapping)
                mapping["product_entitlement_mapping"][gate.PRODUCT]["entitlements"] = entitlements
                self.assert_blocked(mapping=mapping)

    def test_offering_missing_or_ambiguous(self):
        for change in ("missing", "duplicate", "current_unknown"):
            with self.subTest(change=change):
                offerings = copy.deepcopy(self.offerings)
                if change == "missing":
                    offerings["offerings"] = []
                elif change == "duplicate":
                    offerings["offerings"] *= 2
                else:
                    offerings["current_offering_id"] = "unknown"
                self.assert_blocked(offerings=offerings)

    def test_package_missing_or_ambiguous(self):
        for change in ("missing", "duplicate_id", "duplicate_product", "wrong_product"):
            with self.subTest(change=change):
                offerings = copy.deepcopy(self.offerings)
                packages = offerings["offerings"][0]["packages"]
                if change == "missing":
                    packages.clear()
                elif change == "wrong_product":
                    packages[0]["platform_product_identifier"] += ".other"
                else:
                    packages.append(copy.deepcopy(packages[0]))
                    if change == "duplicate_product":
                        packages[1]["identifier"] += "-duplicate"
                self.assert_blocked(offerings=offerings)

    def test_native_named_default_fallback(self):
        offerings = copy.deepcopy(self.offerings)
        offerings["current_offering_id"] = None
        self.assertEqual(gate.validate_live_configuration(self.mapping, offerings)["offering"], "default")

    def test_duplicate_json_identity(self):
        raw = self.raw["offerings.json"]
        # Adversarial duplicate of an actual top-level identity, not a provider observation.
        mutated = b'{"current_offering_id":"other",' + raw.lstrip()[1:]
        with self.assertRaises(gate.ConfigurationError):
            gate.decode_json(mutated)

    def test_payload_bound(self):
        with self.assertRaises(gate.ConfigurationError):
            gate.decode_json(self.raw["mapping.json"] + b" " * gate.MAX_BYTES)


class XcodeConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("xcodebuild"):
            raise unittest.SkipTest("Actual Xcode settings unavailable")
        cls.settings = gate.read_settings()
        cls.release_settings = gate.read_settings(configuration="Release")

    def test_actual_mas_configuration(self):
        key = gate.validate_settings(self.settings)
        self.assertTrue(key.startswith("appl_"))

    def test_actual_old_upload_configuration_is_blocked(self):
        # Xcode omits an empty custom setting from its resolved JSON.
        self.assertEqual(self.release_settings.get("REVENUECAT_PUBLIC_KEY", ""), "")
        with self.assertRaisesRegex(gate.ConfigurationError, "Release-MAS"):
            gate.validate_settings(self.release_settings)

    def test_missing_live_key_blocks_distribution(self):
        for key in ("", "REVENUECAT_PUBLIC_KEY_TODO", "sk_rejected", "test_rejected"):
            with self.subTest(key=key):
                settings = dict(self.settings, REVENUECAT_PUBLIC_KEY=key)
                with self.assertRaisesRegex(gate.ConfigurationError, "public key"):
                    gate.validate_settings(settings)

    def test_appstore_permission_and_network_configuration(self):
        for field, value in (("ENABLE_APP_SANDBOX", "NO"), ("ENABLE_HARDENED_RUNTIME", "NO"),
                             ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "ENABLE_TCC_SPI"),
                             ("OTHER_SWIFT_FLAGS", "-DENABLE_TCC_SPI"),
                             ("CODE_SIGN_ENTITLEMENTS", "Sources/SonanceEQ/Resources/SonanceEQ.entitlements")):
            with self.subTest(field=field):
                with self.assertRaises(gate.ConfigurationError):
                    gate.validate_settings(dict(self.settings, **{field: value}))

    def test_actual_compiled_app_and_missing_key_regression(self):
        configured = os.environ.get("SONANCE_PURCHASE_GATE_TEST_APP")
        if not configured:
            self.skipTest("Actual compiled MAS app not supplied")
        app = Path(configured)
        self.assertEqual(gate.validate_app(app, self.settings)["metadata"], "verified")
        metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        for field in ("RevenueCatPublicKey", "CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString"):
            with self.subTest(field=field):
                mutated = dict(metadata, **{field: ""})
                with self.assertRaisesRegex(gate.ConfigurationError, field):
                    gate.validate_bundle_metadata(mutated, self.settings)


class ProviderHTTPTests(unittest.TestCase):
    """A real aiohttp listener serves retained configuration and protocol failures."""
    @classmethod
    def setUpClass(cls):
        cls.raw = (FIXTURES / "mapping.json").read_bytes()
        cls.status = 200
        cls.content_type = "application/json"
        cls.body = cls.raw
        cls.delay = 0
        cls.stream_slow = False
        cls.observed = []
        cls.loop = asyncio.new_event_loop()
        cls.ready = threading.Event()

        async def handle(request):
            cls.observed.append((request.method, request.path))
            status, content_type, body, delay, stream_slow = cls.status, cls.content_type, cls.body, cls.delay, cls.stream_slow
            if delay:
                await asyncio.sleep(delay)
            if stream_slow:
                response = web.StreamResponse(headers={"Content-Type": "application/json"})
                try:
                    await response.prepare(request)
                    # Actual captured bytes with trailing whitespace, delivered more
                    # frequently than the socket timeout but beyond the total deadline.
                    for byte in cls.raw + b" " * 1024:
                        await response.write(bytes([byte]))
                        await asyncio.sleep(0.05)
                    await response.write_eof()
                except ConnectionResetError:
                    pass
                return response
            response = web.Response(status=status, body=body,
                                    headers={"Content-Type": content_type, "Location": "/redirect-target"})
            try:
                await response.prepare(request)
                await response.write_eof()
            except ConnectionResetError:
                pass  # Expected when the slow-header request has timed out.
            return response

        async def start():
            app = web.Application()
            app.router.add_route("*", "/{tail:.*}", handle)
            cls.runner = web.AppRunner(app)
            await cls.runner.setup()
            site = web.TCPSite(cls.runner, "127.0.0.1", 0)
            await site.start()
            cls.port = site._server.sockets[0].getsockname()[1]
            cls.ready.set()

        def serve():
            asyncio.set_event_loop(cls.loop)
            cls.loop.run_until_complete(start())
            cls.loop.run_forever()
            cls.loop.run_until_complete(cls.runner.cleanup())
            cls.loop.close()

        cls.thread = threading.Thread(target=serve, daemon=True)
        cls.thread.start()
        if not cls.ready.wait(5):
            raise AssertionError("Actual loopback HTTP server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.loop.call_soon_threadsafe(cls.loop.stop)
        cls.thread.join(timeout=5)

    def setUp(self):
        cls = type(self)
        cls.status, cls.content_type, cls.body, cls.delay = 200, "application/json", cls.raw, 0
        cls.stream_slow = False
        cls.observed.clear()

    def read(self, path="/v1/product_entitlement_mapping"):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=0.15)
        # This key is not sent to RevenueCat: protocol tests use a real isolated HTTP listener.
        return gate.read_provider(path, "", connection=connection)

    def test_actual_http_capture_read(self):
        payload, digest = self.read()
        self.assertIn(gate.PRODUCT, payload["product_entitlement_mapping"])
        self.assertEqual(digest, hashlib.sha256(self.raw).hexdigest())
        self.assertEqual(self.observed, [("GET", "/v1/product_entitlement_mapping")])

    def test_http_errors_and_redirects_do_not_become_success(self):
        for status in (301, 302, 401, 403, 429, 500):
            with self.subTest(status=status):
                type(self).status = status
                before = len(self.observed)
                with self.assertRaises(gate.ConfigurationError):
                    self.read()
                self.assertEqual(len(self.observed), before + 1)

    def test_non_json_and_oversized_bodies_are_rejected(self):
        type(self).content_type = "text/html"
        with self.assertRaises(gate.ConfigurationError):
            self.read()
        type(self).content_type = "application/json"
        type(self).body = self.raw + b" " * gate.MAX_BYTES
        with self.assertRaises(gate.ConfigurationError):
            self.read()

    def test_slow_header_socket_timeout(self):
        type(self).delay = 0.4
        with self.assertRaises(TimeoutError):
            self.read()

    def test_trickling_body_cannot_extend_total_deadline(self):
        type(self).stream_slow = True
        started = time.monotonic()
        with self.assertRaisesRegex(gate.ConfigurationTimeout, "deadline"):
            self.read()
        self.assertLess(time.monotonic() - started, 15)

    def test_read_endpoint_allowlist(self):
        for path in ("/v1/receipts", "/v1/subscribers/real-customer", "https://another-origin.example"):
            with self.subTest(path=path):
                with self.assertRaises(gate.ConfigurationError):
                    self.read(path)
        self.assertEqual(self.observed, [])


if __name__ == "__main__":
    unittest.main()
