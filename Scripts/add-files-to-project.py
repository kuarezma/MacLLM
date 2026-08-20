#!/usr/bin/env python3
import hashlib
import re

PBX_PATH = "MacLLM.xcodeproj/project.pbxproj"

def make_id(name: str, kind: str) -> str:
    h = hashlib.md5(f"{kind}:{name}".encode("utf-8")).hexdigest().upper()
    return h[:24]

new_files = [
    # (relative path within group, filename, group_key, build_phase)
    ("Core", "AgentTool.swift", "F7A8B9C0D1E24CF3A4B5C6D7", "Sources"),
    ("Services", "ProjectWorkspaceService.swift", "A8B9C0D1E2F354D4A5B6C7D8", "Sources"),
    ("Services", "DiffEngine.swift", "A8B9C0D1E2F354D4A5B6C7D8", "Sources"),
    ("Services", "CodeSearchService.swift", "A8B9C0D1E2F354D4A5B6C7D8", "Sources"),
    ("Services", "WorkspaceContextAssembler.swift", "A8B9C0D1E2F354D4A5B6C7D8", "Sources"),
    ("Services", "AgentToolExecutor.swift", "A8B9C0D1E2F354D4A5B6C7D8", "Sources"),
    ("Services", "LocalAPIServer.swift", "A8B9C0D1E2F354D4A5B6C7D8", "Sources"),
    ("Features/Workspace", "DiffViewerCardView.swift", "WORKSPACE_GROUP", "Sources"),
    ("Features/Workspace", "TerminalActionCardView.swift", "WORKSPACE_GROUP", "Sources"),
    ("Features/Workspace", "WorkspaceSidebarView.swift", "WORKSPACE_GROUP", "Sources"),
]

with open(PBX_PATH, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add Workspace Group if needed
workspace_group_id = make_id("WorkspaceGroup", "PBXGroup")
if "/* Workspace */ = {" not in content:
    group_entry = f"""\t\t{workspace_group_id} /* Workspace */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
"""
    for folder, fname, group, phase in new_files:
        if folder == "Features/Workspace":
            fileref_id = make_id(fname, "PBXFileReference")
            group_entry += f"\t\t\t\t{fileref_id} /* {fname} */,\n"
    group_entry += """\t\t\t);
\t\t\tpath = Workspace;
\t\t\tsourceTree = "<group>";
\t\t};
"""
    # Insert before Features group
    content = content.replace("/* Begin PBXGroup section */\n", "/* Begin PBXGroup section */\n" + group_entry)

    # Add workspace group to Features group children
    content = content.replace(
        "/* Features */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n",
        f"/* Features */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{workspace_group_id} /* Workspace */,\n"
    )

# 2. Add PBXBuildFile entries
build_files_entries = ""
fileref_entries = ""
sources_entries = ""

for folder, fname, group, phase in new_files:
    build_id = make_id(fname, "PBXBuildFile")
    fileref_id = make_id(fname, "PBXFileReference")

    if build_id not in content:
        build_files_entries += f"\t\t{build_id} /* {fname} in {phase} */ = {{isa = PBXBuildFile; fileRef = {fileref_id} /* {fname} */; }};\n"
        fileref_entries += f"\t\t{fileref_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = \"<group>\"; }};\n"
        sources_entries += f"\t\t\t\t{build_id} /* {fname} in Sources */,\n"

        # Add to Group children if not Features/Workspace
        if group != "WORKSPACE_GROUP":
            pattern = f"({group} /\\* [^*]+ \\*/ = {{\\n\\s+isa = PBXGroup;\\n\\s+children = \\()\\n"
            content = re.sub(pattern, rf"\1\n\t\t\t\t{fileref_id} /* {fname} */,\n", content)

if build_files_entries:
    content = content.replace("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n" + build_files_entries)
    content = content.replace("/* Begin PBXFileReference section */\n", "/* Begin PBXFileReference section */\n" + fileref_entries)
    content = content.replace("/* Begin PBXSourcesBuildPhase section */\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n",
                              f"/* Begin PBXSourcesBuildPhase section */\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{sources_entries}")

with open(PBX_PATH, "w", encoding="utf-8") as f:
    f.write(content)

print("project.pbxproj successfully updated with new files!")
