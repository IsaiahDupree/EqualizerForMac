"""Real configuration projections and real HTTP; no simulated successful writes."""
import asyncio
import copy
import hashlib
import http.client
import importlib.util
import json
import os
import subprocess
import sys
import threading
import time
import unittest
from pathlib import Path

from aiohttp import web

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rc_config", TOOLS / "rc/api.py")
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)
EVIDENCE = Path(__file__).parent / "evidence/rc-scope"


def captures():
    manifest = json.loads((EVIDENCE / "capture.json").read_text())
    result = {}
    for name, observation in manifest["captures"].items():
        raw = (EVIDENCE / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != observation["projection_sha256"]:
            raise AssertionError("Actual configuration projection changed")
        result[name] = json.loads(raw)
    return result


class ScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = captures()
        cls.app = next(a for a in cls.data["apps.json"]["items"] if a["type"] == "app_store")
        cls.product = next(p for p in cls.data["products.json"]["items"]
                           if p["app_id"] == cls.app["id"] and p["store_identifier"].endswith(".monthly"))

    def test_actual_foreign_app_is_rejected_for_sonance(self):
        with self.assertRaisesRegex(rc.gate.ConfigurationError, "Sonance"):
            rc.validate_app(self.app, self.app["project_id"], self.app["id"])

    def test_actual_app_contract_and_wrong_selection(self):
        bundle = self.app["app_store"]["bundle_id"]
        self.assertEqual(rc.validate_app(self.app, self.app["project_id"], self.app["id"], bundle), self.app)
        for app in self.data["apps.json"]["items"]:
            if app["id"] != self.app["id"]:
                with self.subTest(app=app["id"]), self.assertRaises(rc.gate.ConfigurationError):
                    rc.validate_app(app, self.app["project_id"], self.app["id"], bundle)
        with self.assertRaises(rc.gate.ConfigurationError):
            rc.validate_app(self.app, self.app["id"], self.app["id"], bundle)

    def test_product_binding_uses_actual_app_sku_and_type(self):
        args = self.app["id"], self.product["store_identifier"], self.product["type"]
        self.assertEqual(rc.validate_product(self.product, *args), self.product)
        with self.assertRaises(rc.gate.ConfigurationError):
            rc.validate_product(self.product, self.app["id"])
        for field, replacement in (("app_id", self.data["apps.json"]["items"][0]["id"]),
                                   ("store_identifier", rc.IAP), ("type", "non_consumable"),
                                   ("state", "archived"), ("id", None)):
            with self.subTest(field=field), self.assertRaises(rc.gate.ConfigurationError):
                rc.validate_product(dict(self.product, **{field: replacement}), *args)

    def test_actual_cross_platform_package_binding(self):
        rows = self.data["package-products.json"]["items"]
        self.assertTrue(rc.validate_package_products(rows, self.app["id"], self.product))
        with self.assertRaises(rc.gate.ConfigurationError):
            rc.validate_package_products(rows, self.app["id"], None)
        for change in ("sku", "type", "eligibility", "malformed"):
            altered = copy.deepcopy(rows)
            row = next(r for r in altered if r["product"]["app_id"] == self.app["id"])
            if change == "sku":
                row["product"]["store_identifier"] = rc.IAP
            elif change == "type":
                row["product"]["type"] = "non_consumable"
            elif change == "eligibility":
                row["eligibility_criteria"] = "google_sdk_ge_6"
            else:
                row["product"] = None
            with self.subTest(change=change), self.assertRaises(rc.gate.ConfigurationError):
                rc.validate_package_products(altered, self.app["id"], self.product)

    def test_duplicate_lookup_is_not_first_match(self):
        rows = self.data["products.json"]["items"]
        self.assertEqual(rc.unique(rows, "id", self.product["id"]), self.product)
        with self.assertRaisesRegex(rc.gate.ConfigurationError, "Ambiguous"):
            rc.unique(rows + [copy.deepcopy(self.product)], "store_identifier", self.product["store_identifier"])

    def test_default_offering_selection_matches_actual_configuration(self):
        rows = self.data["offerings.json"]["items"]
        self.assertEqual(rc.default_offering(rows), rows[0])
        for change in ("different_current", "unknown_current", "duplicate_current"):
            altered = copy.deepcopy(rows)
            if change == "different_current":
                altered[0]["lookup_key"] = "other"
            elif change == "unknown_current":
                del altered[0]["is_current"]
            else:
                altered *= 2
            with self.subTest(change=change), self.assertRaises(rc.gate.ConfigurationError):
                rc.default_offering(altered)

    def test_one_time_contract_requires_explicit_non_consumable_flag(self):
        # Contract mutations of the actual foreign product, not observed changes
        # to EverReach or evidence that Sonance has this v2 representation.
        for details in (None, {}, {"is_consumable": True}, {"is_consumable": 0}, {"is_consumable": False}):
            altered = dict(self.product, type="one_time", one_time=details)
            args = self.app["id"], self.product["store_identifier"]
            with self.subTest(details=details):
                if details == {"is_consumable": False} and details["is_consumable"] is False:
                    self.assertEqual(rc.validate_product(altered, *args), altered)
                else:
                    with self.assertRaises(rc.gate.ConfigurationError):
                        rc.validate_product(altered, *args)

    def test_apple_environment_does_not_select_a_revenuecat_secret(self):
        env = {k: v for k, v in os.environ.items() if k != "RC_SECRET_KEY"}
        result = subprocess.run(["bash", "-c", 'source "$1" >/dev/null; [[ ! ${RC_SECRET_KEY+x} ]]',
                                 "sonance-scope-test", str(TOOLS / "asc/env.sh")],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)

    def test_missing_explicit_secret_never_searches_other_repos(self):
        env = {k: v for k, v in os.environ.items() if k not in ("RC_SECRET_KEY", "RC_PROJECT_ID", "RC_APP_ID")}
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run([sys.executable, str(TOOLS / "rc/api.py"), "setup"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Set RC_SECRET_KEY explicitly", json.loads(result.stdout)["reason"])

    def test_scope_cannot_be_redefined_by_old_asc_environment(self):
        env = dict(os.environ, APP_BUNDLE_ID=self.app["app_store"]["bundle_id"],
                   IAP_PRODUCT_ID=self.product["store_identifier"], PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([sys.executable, "-c",
                                 "import sys;sys.path.insert(0,sys.argv[1]);import api;print(api.BUNDLE,api.IAP)",
                                 str(TOOLS / "rc")], env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), rc.BUNDLE + " " + rc.IAP)

    def test_explicit_identifiers_reject_paths(self):
        for value in (None, "", "/projects", "app?id=1", "../app", "app%2Fother"):
            with self.subTest(value=value), self.assertRaises(rc.gate.ConfigurationError):
                rc.identifier(value, "RC_APP_ID")


class HTTPCollectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.actual = captures()["apps.json"]
        cls.pid = cls.actual["items"][0]["project_id"]
        cls.path = "/v2/projects/" + cls.pid + "/apps"
        cls.loop = asyncio.new_event_loop()
        cls.ready = threading.Event()
        cls.responses = []
        cls.observed = []

        async def handler(request):
            cls.observed.append((request.method, request.path_qs))
            status, body, content_type, delay = cls.responses.pop(0)
            await asyncio.sleep(delay)
            return web.Response(status=status, body=body, content_type=content_type)

        async def start():
            app = web.Application()
            app.router.add_route("*", "/{tail:.*}", handler)
            cls.runner = web.AppRunner(app)
            await cls.runner.setup()
            site = web.TCPSite(cls.runner, "127.0.0.1", 0)
            await site.start()
            cls.port = site._server.sockets[0].getsockname()[1]
            cls.ready.set()

        def run():
            asyncio.set_event_loop(cls.loop)
            cls.loop.run_until_complete(start())
            cls.loop.run_forever()

        cls.thread = threading.Thread(target=run, daemon=True)
        cls.thread.start()
        if not cls.ready.wait(5):
            raise RuntimeError("Actual loopback listener did not start")

    @classmethod
    def tearDownClass(cls):
        asyncio.run_coroutine_threadsafe(cls.runner.cleanup(), cls.loop).result(timeout=5)
        cls.loop.call_soon_threadsafe(cls.loop.stop)
        cls.thread.join(timeout=5)
        cls.loop.close()

    def setUp(self):
        type(self).responses = []
        type(self).observed = []
        port = self.port

        class LoopbackClient(rc.Client):
            # Exercise production protocol handling with a real local transport.
            def request(self, method, path, body=None, connection=None):
                return super().request(method, path, body, http.client.HTTPConnection("127.0.0.1", port, timeout=1))

        self.client = LoopbackClient("", self.pid)

    def respond(self, page=None, status=200, raw=None, content_type="application/json", delay=0):
        self.responses.append((status, raw if raw is not None else json.dumps(page or self.actual).encode(),
                               content_type, delay))

    def test_actual_apps_collection(self):
        self.respond()
        self.assertEqual(self.client.collection(self.path), self.actual["items"])
        self.assertEqual(self.observed, [("GET", self.path + "?limit=100")])

    def test_foreign_app_blocks_preview_and_apply_without_posts(self):
        aid = next(a["id"] for a in self.actual["items"] if a["type"] == "app_store")
        for apply in (False, True):
            with self.subTest(apply=apply):
                self.respond()
                self.client.apply = apply
                with self.assertRaisesRegex(rc.gate.ConfigurationError, "Sonance"):
                    rc.setup(self.client, aid)
        self.assertTrue(all(method == "GET" for method, _ in self.observed))
        self.assertEqual(len(self.observed), 2)
        self.assertEqual(sum(request["method"] == "POST" for request in self.client.requests), 0)

    def test_read_only_client_rejects_writes_and_foreign_endpoints(self):
        for method, path in (("POST", "/v2/projects/" + self.pid + "/products"),
                             ("GET", "/v2/projects/other/apps"),
                             ("GET", "/v2/projects/" + self.pid + "/customers"),
                             ("GET", "https://api.revenuecat.com" + self.path)):
            with self.subTest(method=method, path=path), self.assertRaises(rc.gate.ConfigurationError):
                self.client.request(method, path)
        self.assertFalse(self.observed)

    def test_apply_client_cannot_create_or_change_apps(self):
        self.client.apply = True
        for path in (self.path, self.path + "/" + self.actual["items"][0]["id"]):
            with self.subTest(path=path), self.assertRaises(rc.gate.ConfigurationError):
                self.client.request("POST", path)
        self.assertFalse(self.observed)

    def test_actual_rows_across_adversarial_page_partition(self):
        # This partition tests pagination; it is not another provider observation.
        first, last = copy.deepcopy(self.actual), copy.deepcopy(self.actual)
        first["items"], last["items"] = first["items"][:1], last["items"][1:]
        cursor = first["items"][-1]["id"]
        first["next_page"] = self.path + "?starting_after=" + cursor
        self.respond(first)
        self.respond(last)
        self.assertEqual(self.client.collection(self.path), self.actual["items"])
        self.assertEqual(self.observed[-1], ("GET", self.path + "?limit=100&starting_after=" + cursor))

    def test_continuation_scope_and_cursor_fail_before_followup(self):
        cursor = self.actual["items"][-1]["id"]
        paths = ("https://example.com" + self.path + "?starting_after=" + cursor,
                 "/v2/projects/other/apps?starting_after=" + cursor,
                 self.path + "?starting_after=other",
                 self.path + "?starting_after=" + cursor + "&starting_after=" + cursor,
                 self.path + "?starting_after=" + cursor + "&limit=1")
        for path in paths:
            with self.subTest(path=path):
                page = copy.deepcopy(self.actual)
                page["next_page"] = path
                self.respond(page)
                count = len(self.observed)
                with self.assertRaises(rc.gate.ConfigurationError):
                    self.client.collection(self.path)
                self.assertEqual(len(self.observed), count + 1)

    def test_incomplete_and_duplicate_collections_are_blocked(self):
        for change in ("terminal_missing", "duplicate", "malformed_association", "empty_continuation"):
            page = copy.deepcopy(self.actual)
            if change == "terminal_missing":
                del page["next_page"]
            elif change == "duplicate":
                page["items"].append(copy.deepcopy(page["items"][0]))
            elif change == "malformed_association":
                page["items"][0] = {"product": "invalid"}
            else:
                page["items"] = []
                page["next_page"] = self.path
            with self.subTest(change=change):
                self.respond(page)
                with self.assertRaises(rc.gate.ConfigurationError):
                    self.client.collection(self.path)

    def test_provider_errors_redirects_payloads_and_duplicate_json(self):
        raw = json.dumps(self.actual).encode()
        for status, body, content_type in ((403, raw, "application/json"), (302, raw, "application/json"),
                                          (200, raw, "text/html"), (200, raw + b" " * rc.gate.MAX_BYTES, "application/json"),
                                          (200, b'{"object":"other",' + raw[1:], "application/json")):
            with self.subTest(status=status, content_type=content_type):
                self.respond(status=status, raw=body, content_type=content_type)
                with self.assertRaises(rc.gate.ConfigurationError):
                    self.client.collection(self.path)

    def test_real_slow_response_obeys_operation_deadline(self):
        self.respond(delay=0.5)
        self.client.deadline = time.monotonic() + 0.15
        start = time.monotonic()
        with self.assertRaises(rc.gate.ConfigurationTimeout):
            self.client.collection(self.path)
        self.assertLess(time.monotonic() - start, 0.45)


if __name__ == "__main__":
    unittest.main()
