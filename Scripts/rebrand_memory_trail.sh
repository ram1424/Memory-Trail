#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

move_if_needed() {
  local source="$1"
  local destination="$2"

  if [ -e "$source" ] && [ ! -e "$destination" ]; then
    mkdir -p "$(dirname "$destination")"
    git mv "$source" "$destination"
  fi
}

move_if_needed "Memory Lane.xcodeproj" "Memory Trails.xcodeproj"
move_if_needed "Memory Trail.xcodeproj" "Memory Trails.xcodeproj"
move_if_needed "MemoryLane" "MemoryTrail"
move_if_needed \
  "Memory Trails.xcodeproj/xcshareddata/xcschemes/Memory Lane.xcscheme" \
  "Memory Trails.xcodeproj/xcshareddata/xcschemes/Memory Trails.xcscheme"
move_if_needed \
  "Memory Trails.xcodeproj/xcshareddata/xcschemes/Memory Trail.xcscheme" \
  "Memory Trails.xcodeproj/xcshareddata/xcschemes/Memory Trails.xcscheme"
move_if_needed \
  "Memory Trails.xcodeproj/xcshareddata/xcschemes/Memory Trail App Store.xcscheme" \
  "Memory Trails.xcodeproj/xcshareddata/xcschemes/Memory Trails App Store.xcscheme"
move_if_needed \
  "MemoryTrail/macOS/MemoryLaneApp.swift" \
  "MemoryTrail/macOS/MemoryTrailApp.swift"
move_if_needed \
  "docs/screenshots/timeline-ui.png" \
  "docs/screenshots/today-ui.png"
move_if_needed \
  "docs/screenshots/ask-memory-lane-ui.png" \
  "docs/screenshots/ask-memory-trail-ui.png"

python3 <<'PY'
from pathlib import Path
import base64
import re

root = Path.cwd()
allowed_suffixes = {
    ".swift", ".pbxproj", ".xcscheme", ".md", ".html", ".json",
    ".yml", ".yaml", ".sh", ".txt"
}
excluded = {
    root / "Scripts" / "rebrand_memory_trail.sh",
}

replacements = (
    ("Memory Lane", "Memory Trails"),
    ("MemoryLane", "MemoryTrail"),
    ("memorylane", "memorytrail"),
    ("MEMORY LANE", "MEMORY TRAILS"),
    ("memory lane", "memory trails"),
    ("generate_app_icons.swift", "generate_memory_trail_icons.swift"),
    ("ask-memory-lane-ui.png", "ask-memory-trail-ui.png"),
    ("timeline-ui.png", "today-ui.png"),
)

for path in root.rglob("*"):
    if not path.is_file() or ".git" in path.parts or path in excluded:
        continue
    # Do not rewrite the workflow while it is using GITHUB_TOKEN to publish the
    # source rename. GitHub rejects workflow-file changes without workflow scope.
    if ".github" in path.parts and "workflows" in path.parts:
        continue
    if path.suffix.lower() not in allowed_suffixes:
        continue

    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue

    # Preserve the one intentional legacy storage path used to migrate
    # existing Memory Trail history into the renamed Memory Trails folder.
    legacy_storage_token = "__MEMORY_TRAIL_LEGACY_STORAGE_PATH__"
    updated = text.replace(
        'appendingPathComponent("Memory Trail", isDirectory: true)',
        legacy_storage_token,
    )

    for old, new in replacements:
        updated = updated.replace(old, new)

    # Keep the singular-to-plural product rename idempotent.
    updated = re.sub(r"Memory Trail(?!s)", "Memory Trails", updated)
    updated = re.sub(r"MEMORY TRAIL(?!S)", "MEMORY TRAILS", updated)
    updated = re.sub(r"memory trail(?!s)", "memory trails", updated)

    updated = updated.replace(
        legacy_storage_token,
        'appendingPathComponent("Memory Trail", isDirectory: true)',
    )

    if updated != text:
        path.write_text(updated, encoding="utf-8")

# Never replace the high-resolution macOS application icon with a custom 64px
# image. The bundle icon and OnboardingIcon asset contain the complete 1x/2x
# representations that the Dock, app switcher, Finder and About panel need.
app_file = root / "MemoryTrail" / "macOS" / "MemoryTrailApp.swift"
if app_file.exists():
    text = app_file.read_text(encoding="utf-8")
    text = text.replace(
        "NSApplication.shared.applicationIconImage = Self.dockIcon",
        "NSApplication.shared.applicationIconImage = Self.brandIcon",
    )
    app_file.write_text(text, encoding="utf-8")

# Refresh embedded website logo/icon data URIs using the current master asset.
# The build workflow repeats this step after regenerating the clean icon.
master = root / "Branding" / "MemoryTrailIconMaster.png"
website = root / "docs" / "index.html"
if master.exists() and website.exists():
    encoded = base64.b64encode(master.read_bytes()).decode("ascii")
    html = website.read_text(encoding="utf-8")
    html = re.sub(
        r"data:image/png;base64,[A-Za-z0-9+/=]+",
        f"data:image/png;base64,{encoded}",
        html,
    )
    website.write_text(html, encoding="utf-8")
PY

# Remove the old generated-icon script after all project references point at the new one.
if [ -e "Scripts/generate_app_icons.swift" ]; then
  git rm "Scripts/generate_app_icons.swift"
fi

# Keep the README logo visible while retaining the current repository URL until
# the GitHub repository slug itself is renamed by the owner.
python3 <<'PY'
from pathlib import Path
readme = Path("README.md")
if readme.exists():
    text = readme.read_text(encoding="utf-8")
    marker = "# Memory Trail\n"
    logo = "\n<p align=\"center\"><img src=\"Branding/MemoryTrailIconMaster.png\" width=\"160\" alt=\"Memory Trail app icon\"></p>\n"
    if marker in text and "Branding/MemoryTrailIconMaster.png" not in text:
        text = text.replace(marker, marker + logo, 1)
    text = text.replace("### Timeline\n", "### Today\n")
    text = text.replace("![Memory Trails Timeline](docs/screenshots/today-ui.png)", "![Memory Trails Today view](docs/screenshots/today-ui.png)")
    readme.write_text(text, encoding="utf-8")
PY

printf 'Memory Trails rebrand and macOS icon safeguards applied successfully.\n'
