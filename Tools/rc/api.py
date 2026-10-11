#!/usr/bin/env python3
"""Explicitly scoped RevenueCat configuration. setup previews; setup --apply writes.

Only RC_SECRET_KEY is read for authentication. RC_PROJECT_ID and RC_APP_ID must
identify the existing Sonance App Store app; no app or project is auto-created.
"""
import argparse
import hashlib
import http.client
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_mas_purchase_config as gate

BUNDLE = gate.BUNDLE
IAP = gate.PRODUCT
ENTITLEMENT = "pro"
OFFERING = "default"
PACKAGE = "lifetime"
MAX_PAGES = 20
MAX_ROWS = 2000


def identifier(value, name):
    gate.require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,255}", value),
                 "Explicit valid " + name + " is required")
    return value


def secret():
    value = os.environ.get("RC_SECRET_KEY", "")
    gate.require(re.fullmatch(r"sk_[A-Za-z0-9]{8,256}", value) is not None,
                 "Set RC_SECRET_KEY explicitly to the Sonance project secret; no credential search is performed")
    return value


def project_id():
    return identifier(os.environ.get("RC_PROJECT_ID"), "RC_PROJECT_ID")


class Client:
    def __init__(self, key, pid=None, apply=False):
        self._key = key
        self.pid = pid
        self.apply = apply
        self.deadline = time.monotonic() + 90
        self.observations = []
        self.requests = []

    def request(self, method, path, body=None, connection=None):
        parsed = urlsplit(path)
        gate.require(not parsed.scheme and not parsed.netloc and not parsed.fragment,
                     "Only fixed-origin configuration paths are allowed")
        gate.require(path.startswith("/v2/projects") and ".." not in path and "%" not in parsed.path,
                     "Unsupported RevenueCat configuration path")
        scope = "/v2/projects/" + self.pid if self.pid else None
        gate.require(parsed.path == "/v2/projects" or
                     (scope is not None and re.fullmatch(re.escape(scope) +
                      r"/(?:apps|products|entitlements|offerings|packages)(?:/[A-Za-z0-9_-]+)?"
                      r"(?:/(?:products|packages|public_api_keys|actions/attach_products))?", parsed.path)),
                     "Configuration endpoint is outside the explicit project")
        gate.require(method == "GET" or (method == "POST" and self.apply and scope is not None
                     and parsed.path.startswith(scope + "/") and "/apps" not in parsed.path),
                     "Writes require setup --apply and cannot create or modify apps")
        remaining = self.deadline - time.monotonic()
        gate.require(remaining > 0, "Configuration operation exceeded 90 seconds")
        connection = connection or http.client.HTTPSConnection("api.revenuecat.com", timeout=min(5, remaining))
        raw_body = json.dumps(body).encode() if body is not None else None
        try:
            with gate.request_deadline(min(12, remaining)):
                self.requests.append({"method": method, "path": path})
                connection.request(method, path, body=raw_body, headers={
                    "Authorization": "Bearer " + self._key,
                    "Content-Type": "application/json", "Accept": "application/json"})
                response = connection.getresponse()
                gate.require(200 <= response.status < 300, "RevenueCat configuration HTTP " + str(response.status))
                length = response.getheader("Content-Length")
                gate.require(length is None or (length.isdecimal() and int(length) <= gate.MAX_BYTES),
                             "Configuration response exceeds size limit")
                raw = response.read(gate.MAX_BYTES + 1)
                gate.require(not raw or response.getheader("Content-Type", "").split(";")[0] == "application/json",
                             "Configuration response is not JSON")
                value = gate.decode_json(raw) if raw else {}
                gate.require(isinstance(value, dict), "Invalid configuration object")
                self.observations.append({"method": method, "path": path, "status": response.status,
                                          "body_sha256": hashlib.sha256(raw).hexdigest()})
                return value
        finally:
            connection.close()

    def collection(self, path):
        rows, seen = [], set()
        cursor = None
        for _ in range(MAX_PAGES):
            query = {"limit": 100}
            if cursor:
                query["starting_after"] = cursor
            page = self.request("GET", path + "?" + urlencode(query))
            gate.require(page.get("object") == "list" and isinstance(page.get("items"), list)
                         and "next_page" in page, "Incomplete configuration collection")
            batch = page["items"]
            gate.require(len(batch) <= 100 and len(rows) + len(batch) <= MAX_ROWS,
                         "Configuration collection exceeds capacity")
            for row in batch:
                gate.require(isinstance(row, dict), "Invalid configuration row")
                identity = resource_id(row)
                gate.require(identity not in seen, "Duplicate configuration identity")
                seen.add(identity)
            rows.extend(batch)
            next_page = page["next_page"]
            if next_page is None:
                return rows
            gate.require(isinstance(next_page, str) and bool(batch), "Invalid configuration continuation")
            parsed = urlsplit(next_page)
            gate.require(parsed.path == path and not parsed.fragment and
                         (not parsed.scheme and not parsed.netloc or
                          parsed.scheme == "https" and parsed.netloc == "api.revenuecat.com"),
                         "Continuation changed origin or configuration scope")
            args = parse_qs(parsed.query, keep_blank_values=True)
            cursor = resource_id(batch[-1])
            gate.require(set(args) <= {"starting_after", "limit"} and args.get("starting_after") == [cursor]
                         and ("limit" not in args or args["limit"] == ["100"]), "Invalid configuration cursor")
        raise gate.ConfigurationError("Configuration collection is incomplete at the page limit")


def resource_id(row):
    product = row.get("product")
    return identifier(row.get("id") or (product.get("id") if isinstance(product, dict) else None), "resource identity")


def unique(items, field, value):
    matches = [item for item in items if item.get(field) == value]
    gate.require(len(matches) <= 1, "Ambiguous configuration lookup: " + field)
    return matches[0] if matches else None


def validate_app(app, pid, aid, bundle=BUNDLE):
    gate.require(isinstance(app, dict) and app.get("id") == aid and app.get("project_id") == pid,
                 "App does not belong to the explicit project/app selection")
    store = app.get("type")
    gate.require(store in ("app_store", "mac_app_store") and
                 isinstance(app.get(store), dict) and app[store].get("bundle_id") == bundle,
                 "Selected app is not the Sonance App Store bundle")
    return app


def validate_product(product, aid, sku=IAP, kind="non_consumable"):
    purchase_type = product.get("type") if isinstance(product, dict) else None
    if kind == "non_consumable" and purchase_type == "one_time":
        details = product.get("one_time")
        purchase_type = "non_consumable" if isinstance(details, dict) and details.get("is_consumable") is False else None
    gate.require(isinstance(product, dict) and product.get("app_id") == aid
                 and product.get("store_identifier") == sku and purchase_type == kind,
                 "Product app, SKU or purchase type conflicts with the approved product")
    identifier(product.get("id"), "product identity")
    gate.require(product.get("state") == "active", "Approved product is not active")
    return product


def validate_package_products(rows, aid, product):
    linked = False
    for row in rows:
        other = row.get("product")
        gate.require(isinstance(other, dict), "Invalid package product association")
        identifier(other.get("app_id"), "associated app identity")
        if other["app_id"] == aid:
            gate.require(product is not None and other.get("id") == product["id"]
                         and other.get("store_identifier") == product["store_identifier"]
                         and other.get("type") == product["type"] and row.get("eligibility_criteria") == "all",
                         "Package contains a conflicting product for the selected app")
            linked = True
    return linked


def default_offering(rows):
    gate.require(all(isinstance(row.get("is_current"), bool) for row in rows),
                 "Offering selection is unknown")
    current = [row for row in rows if row["is_current"]]
    off = unique(rows, "lookup_key", OFFERING)
    gate.require(len(current) <= 1 and (not current or off is not None and current[0]["id"] == off["id"]),
                 "Another offering is current; setup cannot change the app's offering selection")
    return off


def preflight(client, aid):
    pid = client.pid
    base = "/v2/projects/" + pid
    app = unique(client.collection(base + "/apps"), "id", aid)
    validate_app(app, pid, aid)
    settings = gate.read_settings()
    public_key = gate.validate_settings(settings)
    keys = client.collection(base + "/apps/" + aid + "/public_api_keys")
    matches = [key for key in keys if key.get("key") == public_key]
    gate.require(len(matches) == 1 and matches[0].get("app_id") == aid
                 and matches[0].get("environment") == "production",
                 "Resolved App Store SDK key does not belong to the selected app")
    product = unique(client.collection(base + "/products"), "store_identifier", IAP)
    if product:
        validate_product(product, aid)
    ent = unique(client.collection(base + "/entitlements"), "lookup_key", ENTITLEMENT)
    if ent:
        gate.require(ent.get("project_id") == pid, "Entitlement is outside the selected project")
    off = default_offering(client.collection(base + "/offerings"))
    pkg = unique(client.collection(base + "/offerings/" + off["id"] + "/packages"),
                 "lookup_key", PACKAGE) if off else None
    ent_links = client.collection(base + "/entitlements/" + ent["id"] + "/products") if ent else []
    for linked in ent_links:
        identifier(linked.get("app_id"), "entitlement product app identity")
        if linked["app_id"] == aid:
            gate.require(product is not None and linked.get("id") == product["id"],
                         "Pro entitlement contains a conflicting product for the selected app")
            validate_product(linked, aid)
    ent_attached = product is not None and any(link.get("id") == product["id"] for link in ent_links)
    pkg_links = client.collection(base + "/packages/" + pkg["id"] + "/products") if pkg else []
    pkg_attached = validate_package_products(pkg_links, aid, product)
    actions = ["create_" + name for name, row in (("product", product), ("entitlement", ent),
                                                ("offering", off), ("package", pkg)) if row is None]
    if not ent_attached:
        actions.append("attach_product_to_pro")
    if not pkg_attached:
        actions.append("attach_product_to_lifetime")
    return {"app": app, "product": product, "entitlement": ent, "offering": off, "package": pkg,
            "actions": actions, "public_sdk_sha256": hashlib.sha256(public_key.encode()).hexdigest()}


def setup(client, aid):
    state = preflight(client, aid)
    base = "/v2/projects/" + client.pid

    def write(path, body):
        # Recheck the existing app immediately before every provider mutation.
        validate_app(client.request("GET", base + "/apps/" + aid), client.pid, aid)
        return client.request("POST", path, body)

    if client.apply and state["actions"]:
        product = state["product"] or write(base + "/products", {
            "store_identifier": IAP, "app_id": aid, "type": "non_consumable"})
        validate_product(product, aid)
        ent = state["entitlement"] or write(base + "/entitlements", {"lookup_key": ENTITLEMENT, "display_name": "Pro"})
        gate.require(ent.get("lookup_key") == ENTITLEMENT and ent.get("project_id") == client.pid,
                     "Created entitlement has unexpected identity")
        identifier(ent.get("id"), "entitlement identity")
        off = state["offering"] or write(base + "/offerings", {"lookup_key": OFFERING, "display_name": "Default"})
        gate.require(off.get("lookup_key") == OFFERING, "Created offering has unexpected identity")
        identifier(off.get("id"), "offering identity")
        pkg = state["package"] or write(base + "/offerings/" + off["id"] + "/packages", {
            "lookup_key": PACKAGE, "display_name": "Lifetime Pro"})
        gate.require(pkg.get("lookup_key") == PACKAGE, "Created package has unexpected identity")
        identifier(pkg.get("id"), "package identity")
        if "attach_product_to_pro" in state["actions"]:
            write(base + "/entitlements/" + ent["id"] + "/actions/attach_products", {"product_ids": [product["id"]]})
        if "attach_product_to_lifetime" in state["actions"]:
            write(base + "/packages/" + pkg["id"] + "/actions/attach_products", {
                "products": [{"product_id": product["id"], "eligibility_criteria": "all"}]})
        state = preflight(client, aid)
        gate.require(not state["actions"], "Configuration writes did not produce the requested bindings")
    return {"schema": "sonance_revenuecat_setup_v1", "status": "configuration_verified" if not state["actions"] else "preview",
            "dry_run": not client.apply, "project_id": client.pid, "app_id": aid, "bundle_id": BUNDLE,
            "product": IAP, "pending_actions": state["actions"], "public_sdk_sha256": state["public_sdk_sha256"],
            "provider_observations": client.observations, "customer_payment_verified": False,
            "provider_write_attempts": sum(request["method"] == "POST" for request in client.requests),
            "receipt_to_entitlement_verified": False, "release_acceptance": "pending"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("projects", "apps", "setup"), nargs="?", default="projects")
    parser.add_argument("--apply", action="store_true", help="Apply a validated setup plan; default is read-only")
    args = parser.parse_args()
    client = None
    try:
        gate.require(not args.apply or args.command == "setup", "--apply is only supported for setup")
        key = secret()
        pid = project_id() if args.command != "projects" else None
        client = Client(key, pid, apply=args.apply)
        if args.command == "projects":
            value = [{"id": row["id"], "name": row.get("name")} for row in client.collection("/v2/projects")]
        elif args.command == "apps":
            value = [{"id": row["id"], "type": row.get("type"), "name": row.get("name"),
                      "bundle_id": (row.get("app_store") or row.get("mac_app_store") or {}).get("bundle_id")}
                     for row in client.collection("/v2/projects/" + pid + "/apps")]
        else:
            aid = identifier(os.environ.get("RC_APP_ID"), "RC_APP_ID")
            value = setup(client, aid)
        print(json.dumps(value, indent=2))
        return 0
    except (gate.ConfigurationError, OSError, http.client.HTTPException, json.JSONDecodeError) as error:
        # Do not echo provider error bodies, request headers or credentials.
        detail = str(error) if isinstance(error, gate.ConfigurationError) else type(error).__name__
        print(json.dumps({"schema": "sonance_revenuecat_setup_v1", "status": "blocked", "reason": detail,
                          "provider_observations": client.observations if client else [],
                          "provider_write_attempts": sum(request["method"] == "POST" for request in client.requests) if client else 0,
                          "release_acceptance": "pending"}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
