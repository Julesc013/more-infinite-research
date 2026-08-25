import argparse
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
import mir4_api_v1 as mir4
parser=argparse.ArgumentParser();parser.add_argument("path",type=Path);args=parser.parse_args()
response=mir4.validate(mir4.parse(args.path.read_text(encoding="utf-8")))
print({"target":response["target"]["id"],"surface":response["surface"],"available":mir4.decode_availability(response)["available"],"items":len(response["items"]),"digest":response["digest"]})