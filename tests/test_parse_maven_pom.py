import subprocess
import sys
import unittest
from pathlib import Path


PARSER = Path(__file__).resolve().parents[1] / ".github/actions/check-critical-vulns/parse_maven_pom.py"


class ParseMavenPomTests(unittest.TestCase):
    def test_direct_dependency_uses_root_property_version(self):
        pom = """<project xmlns="http://maven.apache.org/POM/4.0.0">
          <properties><swagger.version>2.10.5</swagger.version></properties>
          <dependencies><dependency>
            <groupId>io.springfox</groupId>
            <artifactId>springfox-swagger-ui</artifactId>
            <version>${swagger.version}</version>
          </dependency></dependencies>
        </project>"""

        completed = subprocess.run(
            [sys.executable, str(PARSER), "io.springfox:springfox-swagger-ui"],
            input=pom,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.strip(), "2.10.5")

    def test_profile_override_keeps_dependency_unverifiable(self):
        pom = """<project xmlns="http://maven.apache.org/POM/4.0.0">
          <dependencies><dependency>
            <groupId>io.springfox</groupId>
            <artifactId>springfox-swagger-ui</artifactId>
            <version>2.10.5</version>
          </dependency></dependencies>
          <profiles><profile><id>legacy</id><dependencies><dependency>
            <groupId>io.springfox</groupId>
            <artifactId>springfox-swagger-ui</artifactId>
            <version>2.7.0</version>
          </dependency></dependencies></profile></profiles>
        </project>"""

        completed = subprocess.run(
            [sys.executable, str(PARSER), "io.springfox:springfox-swagger-ui"],
            input=pom,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertNotEqual(completed.returncode, 0)


if __name__ == "__main__":
    unittest.main()
