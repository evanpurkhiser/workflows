# Receiver and deployment policy:
# https://github.com/evanpurkhiser/ansible-personal/tree/main/roles/machines/server/service-deploy-image

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

endpoint = "https://apis.evanpurkhiser.com/deploy-image"
audience = urllib.parse.urlencode({"audience": endpoint})
token_url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&" + audience
body = json.dumps(
    {
        "image": f"ghcr.io/{os.environ['GITHUB_REPOSITORY']}:latest",
        "digest": os.environ["IMAGE_DIGEST"],
        "sha": os.environ["GITHUB_SHA"],
        "run_id": os.environ["GITHUB_RUN_ID"],
        "run_attempt": os.environ["GITHUB_RUN_ATTEMPT"],
    }
).encode()

for attempt in range(4):
    try:
        token_request = urllib.request.Request(
            token_url,
            headers={
                "Authorization": f"Bearer {os.environ['ACTIONS_ID_TOKEN_REQUEST_TOKEN']}",
            },
        )
        with urllib.request.urlopen(token_request, timeout=30) as response:
            token = json.load(response)["value"]
        print(f"::add-mask::{token}", flush=True)

        request = urllib.request.Request(
            endpoint,
            data=body,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 202:
                raise SystemExit(f"Unexpected deployment response: {response.status}")
        print(f"Image update request accepted: {os.environ['IMAGE_DIGEST']}")
        break
    except urllib.error.HTTPError as error:
        if error.code < 500 and error.code not in (408, 429):
            raise SystemExit(
                f"Deployment request rejected: HTTP {error.code}"
            ) from None
    except (urllib.error.URLError, TimeoutError):
        pass

    if attempt == 3:
        raise SystemExit("Could not deliver image update request after four attempts")
    time.sleep(5 * (attempt + 1))
