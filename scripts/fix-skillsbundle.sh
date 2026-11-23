#!/bin/bash
# xcodegen can't express Xcode's `wrapper.skillsbundle` file type, so patch it into the generated project.
# Without it Xcode copies Skills.skillsbundle verbatim instead of compiling it into Metadata.appintents/Skills.skillsc.
set -euo pipefail
PBX="$(dirname "$0")/../AIBank.xcodeproj/project.pbxproj"
/usr/bin/sed -i '' 's|isa = PBXFileReference; path = Skills.skillsbundle;|isa = PBXFileReference; lastKnownFileType = wrapper.skillsbundle; path = Skills.skillsbundle;|' "$PBX"
