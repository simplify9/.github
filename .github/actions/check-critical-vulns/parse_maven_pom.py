#!/usr/bin/env python3
"""Print a direct Maven dependency's explicit version from a pom.xml on stdin.

Only a literal version or a property defined in the same POM is accepted.
Missing, inherited, and profile-dependent versions stay unverifiable.
"""

import sys
import xml.etree.ElementTree as ET


def child(parent: ET.Element, name: str) -> ET.Element | None:
    return next((element for element in parent if element.tag.rsplit("}", 1)[-1] == name), None)


def children(parent: ET.Element, name: str) -> list[ET.Element]:
    return [element for element in parent if element.tag.rsplit("}", 1)[-1] == name]


def coordinate(dependency: ET.Element) -> str:
    group = child(dependency, "groupId")
    artifact = child(dependency, "artifactId")
    return f"{group.text}:{artifact.text}" if group is not None and artifact is not None else ""


def main() -> int:
    wanted = sys.argv[1]
    try:
        root = ET.fromstring(sys.stdin.read())
    except ET.ParseError as error:
        print(f"Invalid pom.xml: {error}", file=sys.stderr)
        return 1

    dependencies = child(root, "dependencies")
    matches = [dependency for dependency in children(dependencies, "dependency") if coordinate(dependency) == wanted] if dependencies is not None else []
    if len(matches) != 1:
        return 1

    profiles = child(root, "profiles")
    for profile in children(profiles, "profile") if profiles is not None else []:
        profile_dependencies = child(profile, "dependencies")
        if profile_dependencies is not None and any(coordinate(dependency) == wanted for dependency in children(profile_dependencies, "dependency")):
            return 1

    version_element = child(matches[0], "version")
    version = (version_element.text or "").strip() if version_element is not None else ""
    if version.startswith("${") and version.endswith("}"):
        property_name = version[2:-1]
        properties = child(root, "properties")
        property_element = child(properties, property_name) if properties is not None else None
        version = (property_element.text or "").strip() if property_element is not None else ""
        if profiles is not None:
            for profile in children(profiles, "profile"):
                profile_properties = child(profile, "properties")
                if profile_properties is not None and child(profile_properties, property_name) is not None:
                    return 1

    if not version or "${" in version:
        return 1
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
