import os
import re
import json
import base64
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from credentials import JENKINS_URL, JENKINS_TOKEN, JENKINS_USER, JENKINS_API_TOKEN

# Pattern to match files like "<username>_output_<timestamp>.json"
PATTERN = re.compile(r"^.*_output_\d+\.json$")
# Non-sensitive default
JOB_NAME = os.environ.get("JOB_NAME", "terraform-deploy")

def lambda_handler(event, context):
    for rec in event["Records"]:
        key = rec["s3"]["object"]["key"]
        bucket = rec["s3"]["bucket"]["name"]
        if not PATTERN.match(key):
            print(f"Skipping file {key}: does not match pattern")
            continue

        params = urlencode({
            "token": JENKINS_TOKEN,
            "BUCKET": bucket,
            "KEY": key
        })
        url = f"{JENKINS_URL}/job/{JOB_NAME}/buildWithParameters?{params}"
        print(f"Attempting to trigger Jenkins at: {url}")

        auth = base64.b64encode(f"{JENKINS_USER}:{JENKINS_API_TOKEN}".encode()).decode()
        req = Request(url, method="POST")
        req.add_header("Authorization", f"Basic {auth}")

        try:
            with urlopen(req) as resp:
                print(f"Triggered Jenkins for {key}: {resp.status} {resp.reason}")
        except HTTPError as e:
            print(f"HTTP error triggering Jenkins for {key}: {e.code} {e.reason}")
        except URLError as e:
            print(f"URL error triggering Jenkins for {key}: {e.reason}")
        except Exception as e:
            print(f"Unexpected error triggering Jenkins for {key}: {str(e)}")

    return {"status": "done"}
