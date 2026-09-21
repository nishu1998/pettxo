"""Plan or explicitly apply customer-visible slot counts from occupancy.

Usage: python3 functions/scripts/slot_capacity_projection_dry_run.py --project PROJECT
Default mode never writes Firestore. Apply is reserved for a separately
approved migration and uses each slot's observed updateTime as a precondition.
"""

import argparse
import concurrent.futures
import json
import subprocess
from datetime import datetime, timezone
import urllib.error
import urllib.parse
import urllib.request


def integer(document, field, default=0):
    raw = document.get("fields", {}).get(field, {})
    return int(raw.get("integerValue", default))


def fetch(request):
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--apply-future-only", action="store_true")
    parser.add_argument("--confirmed-approval", default="")
    args = parser.parse_args()
    if args.apply_future_only and args.confirmed_approval != args.project:
        parser.error("Applying requires --confirmed-approval PROJECT after explicit authorization")
    token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
    base = f"https://firestore.googleapis.com/v1/projects/{args.project}/databases/(default)/documents"
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    query = {"structuredQuery": {"from": [{"collectionId": "slotOccupancy", "allDescendants": True}]}}
    request = urllib.request.Request(base + ":runQuery", data=json.dumps(query).encode(), headers=headers)
    rows = fetch(request)
    occupancy = [row["document"] for row in rows if "document" in row]
    occupancy_by_path = {document["name"].split("/documents/", 1)[1]: document for document in occupancy}
    bookings_query = {"structuredQuery": {"from": [{"collectionId": "bookings"}]}}
    bookings_request = urllib.request.Request(base + ":runQuery", data=json.dumps(bookings_query).encode(), headers=headers)
    bookings = [row["document"] for row in fetch(bookings_request) if "document" in row]
    blocking_states = {"CONFIRMED", "IN_PROGRESS", "COMPLETED_PENDING_REVIEW",
                       "UNDER_DISPUTE", "COMPLETED_FINAL", "NO_SHOW"}
    future_claim_issues = []
    for booking in bookings:
        fields = booking.get("fields", {})
        if fields.get("bookingType", {}).get("stringValue") != "SLOT" or \
                fields.get("state", {}).get("stringValue") not in blocking_states:
            continue
        booking_id = booking["name"].rsplit("/", 1)[1]
        service_id = fields.get("serviceId", {}).get("stringValue", "")
        slots = fields.get("schedule", {}).get("mapValue", {}).get("fields", {}).get("slots", {}).get("arrayValue", {}).get("values", [])
        for entry in slots:
            slot_fields = entry.get("mapValue", {}).get("fields", {})
            slot_id = slot_fields.get("slotId", {}).get("stringValue", "")
            start_at = slot_fields.get("startAt", {}).get("timestampValue", "")
            if not start_at or datetime.fromisoformat(start_at.replace("Z", "+00:00")) <= datetime.now(timezone.utc):
                continue
            path = f"services/{service_id}/slotOccupancy/{slot_id}"
            claims = occupancy_by_path.get(path, {}).get("fields", {}).get("bookingClaims", {}).get("mapValue", {}).get("fields", {})
            if int(claims.get(booking_id, {}).get("integerValue", "0")) < 1:
                future_claim_issues.append({"bookingId": booking_id, "occupancyPath": path,
                                            "issue": "future_confirmed_claim_missing"})

    def compare(document):
        path = document["name"].split("/documents/", 1)[1]
        parts = path.split("/")
        if len(parts) != 4 or parts[0] != "services" or parts[2] != "slotOccupancy":
            return {"occupancyPath": path, "issue": "unexpected_path"}
        service_id, slot_id = parts[1], parts[3]
        slot_path = f"services/{service_id}/slots/{slot_id}"
        url = base + "/" + urllib.parse.quote(slot_path, safe="/")
        slot = fetch(urllib.request.Request(url, headers=headers))
        claimed = integer(document, "confirmedUnits")
        if claimed < 0:
            return {"occupancyPath": path, "issue": "negative_occupancy"}
        if slot is None:
            return {"occupancyPath": path, "slotPath": slot_path, "issue": "missing_slot"}
        projected = integer(slot, "acceptedCount")
        if projected == claimed:
            return None
        start_at = slot.get("fields", {}).get("startAt", {}).get("timestampValue", "")
        future = bool(start_at and datetime.fromisoformat(start_at.replace("Z", "+00:00")) > datetime.now(timezone.utc))
        return {"slotPath": slot_path, "observedUpdateTime": slot["updateTime"],
                "acceptedCount": projected, "proposedAcceptedCount": claimed,
                "slotStartAt": start_at, "future": future}

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        findings = [item for item in pool.map(compare, occupancy) if item is not None]
    proposed = [item for item in findings if "proposedAcceptedCount" in item]
    issues = [item for item in findings if "issue" in item]
    print(json.dumps({"project": args.project, "occupancyDocuments": len(occupancy),
                      "proposedPatchCount": len(proposed),
                      "futureProposedPatchCount": sum(item["future"] for item in proposed),
                      "issueCount": len(issues) + len(future_claim_issues),
                      "proposedPatches": proposed, "issues": issues + future_claim_issues}, indent=2))
    if args.apply_future_only:
        if issues or future_claim_issues:
            raise SystemExit("Refusing to apply while occupancy issues exist")
        applied = 0
        for item in proposed:
            if not item["future"]:
                continue
            mask = urllib.parse.urlencode({"updateMask.fieldPaths": "acceptedCount",
                                          "currentDocument.updateTime": item["observedUpdateTime"]})
            url = base + "/" + urllib.parse.quote(item["slotPath"], safe="/") + "?" + mask
            body = {"fields": {"acceptedCount": {"integerValue": str(item["proposedAcceptedCount"])}}}
            if fetch(urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method="PATCH")) is None:
                raise SystemExit("Slot disappeared before its conditional patch: " + item["slotPath"])
            applied += 1
        print(json.dumps({"appliedFutureSlotCount": applied}))


if __name__ == "__main__":
    main()
