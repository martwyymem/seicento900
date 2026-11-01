"""Plans the Goliath (the final race: one lap of the whole Brzeszcze open world). Kept for its old command line;
the planner and the Goliath's waypoints now live in plan_route.py (ROUTES['goliath']):

    cd tools && python3 plan_goliath.py && python3 build_street_tracks.py goliath --check /tmp/goliath.png
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plan_route  # noqa: E402

if __name__ == '__main__':
    plan_route.plan('goliath')
