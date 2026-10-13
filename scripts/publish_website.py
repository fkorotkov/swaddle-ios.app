#!/usr/bin/env python3
"""Update only website files in the shared private app repository."""
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/fkorotkov/swaddle-ios.app.git"
PAYLOAD = ("website", "scripts/verify_website.py", ".github/workflows/website.yml")


def run(*args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, check=True)


def main():
    run("python3", "scripts/verify_website.py")
    with tempfile.TemporaryDirectory(prefix="swaddle-website-") as temp:
        checkout = Path(temp) / "site"
        run("git", "clone", "--depth", "1", REPOSITORY, str(checkout))
        for relative in PAYLOAD:
            source, target = ROOT / relative, checkout / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                # Only replace the website directory in our fresh temporary clone.
                if target.exists(): shutil.rmtree(target)
                shutil.copytree(source, target)
            else:
                shutil.copy2(source, target)
        run("python3", "scripts/verify_website.py", cwd=checkout)
        run("git", "add", *PAYLOAD, cwd=checkout)
        changed = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=checkout)
        if changed.returncode == 0:
            print("Website already matches the published repository.")
            return
        if changed.returncode != 1:
            raise RuntimeError("Unable to inspect website changes")
        run("git", "config", "user.name", "Fedor Korotkov", cwd=checkout)
        run("git", "config", "user.email", "fedor.korotkov@gmail.com", cwd=checkout)
        run("git", "commit", "-m", "Update Swaddle website", cwd=checkout)
        run("git", "push", "origin", "HEAD:main", cwd=checkout)
    print("Published source. Check the GitHub Actions Pages deployment before claiming it is live.")


if __name__ == "__main__":
    main()
