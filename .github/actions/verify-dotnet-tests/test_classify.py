import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr

import classify as c

TEST_SDK = '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.10.0" />%s</ItemGroup></Project>'


def ref(name):
    return '<PackageReference Include="%s" Version="1.0.0" />' % name


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    return path


class ProjectInfo(unittest.TestCase):
    def test_test_sdk_marks_test_project(self):
        self.assertTrue(c.project_info(TEST_SDK % "")["test"])
        self.assertFalse(c.project_info('<Project Sdk="Microsoft.NET.Sdk.Web"></Project>')["test"])

    def test_istestproject_and_mstest_sdk(self):
        self.assertTrue(c.project_info("<Project><PropertyGroup><IsTestProject>true</IsTestProject></PropertyGroup></Project>")["test"])
        self.assertTrue(c.project_info('<Project Sdk="MSTest.Sdk/3.6.4"></Project>')["test"])

    def test_testcontainers_prefix_is_integration(self):
        self.assertTrue(c.project_info(TEST_SDK % ref("Testcontainers.PostgreSql"))["testcontainers"])
        self.assertTrue(c.project_info(TEST_SDK % ref("Testcontainers"))["testcontainers"])
        self.assertFalse(c.project_info(TEST_SDK % ref("TestcontainersLookalike"))["testcontainers"])

    def test_mvc_testing_detected(self):
        self.assertTrue(c.project_info(TEST_SDK % ref("Microsoft.AspNetCore.Mvc.Testing"))["mvc_testing"])

    def test_reference_any_attribute_order_and_quotes(self):
        text = "<Project><ItemGroup><PackageReference Version=\"4.16.0\" Include='Testcontainers.PostgreSql' />" \
               "<PackageReference\n    Include = \"Microsoft.NET.Test.Sdk\"\n    Version=\"18.10.0\" /></ItemGroup></Project>"
        info = c.project_info(text)
        self.assertTrue(info["testcontainers"])
        self.assertTrue(info["test"])

    def test_update_is_not_a_reference(self):
        self.assertFalse(c.project_info('<Project><PackageReference Update="Testcontainers" Version="1" /></Project>')["testcontainers"])

    def test_clients_exact_and_prefix(self):
        text = "<Project>%s%s%s</Project>" % (ref("Npgsql.EntityFrameworkCore.PostgreSQL"), ref("StackExchange.Redis"),
                                              ref("Newtonsoft.Json"))
        self.assertEqual(c.project_info(text)["clients"], ["Npgsql.EntityFrameworkCore.PostgreSQL", "StackExchange.Redis"])


class Classify(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def kinds(self):
        return {p["path"]: p["kind"] for p in c.classify(self.d)}

    def test_refused_names_file_line_never_value(self):
        write(self.d, "Real.Tests/Real.Tests.csproj", TEST_SDK % "")
        write(self.d, "Real.Tests/appsettings.json", '{\n  "Db": "Host=db.example.co;Password=s3cr3tvalue"\n}\n')
        buf = io.StringIO()
        with redirect_stderr(buf):
            found = c.refusals(os.path.join(self.d, "Real.Tests"))
        self.assertEqual(found, ["appsettings.json:2 connection-string"])
        self.assertEqual(self.kinds(), {"Real.Tests/Real.Tests.csproj": "refused"})
        self.assertNotIn("s3cr3t", buf.getvalue() + repr(c.classify(self.d)))

    def test_local_connection_string_not_refused(self):
        write(self.d, "Db.Tests/Db.Tests.csproj", TEST_SDK % "")
        write(self.d, "Db.Tests/appsettings.json", '{"Db": "Host=localhost;Password=postgres"}')
        self.assertEqual(self.kinds(), {"Db.Tests/Db.Tests.csproj": "unit"})

    def test_email_in_fixture_not_refused(self):
        write(self.d, "Api.Tests/Api.Tests.csproj", TEST_SDK % ref("Testcontainers.PostgreSql"))
        write(self.d, "Api.Tests/Fixtures/requests.json", '{"email": "jane@client.example.co"}')
        self.assertEqual(self.kinds(), {"Api.Tests/Api.Tests.csproj": "integration"})

    def test_refused_wins_over_integration(self):
        write(self.d, "X.Tests/X.Tests.csproj", TEST_SDK % ref("Testcontainers"))
        write(self.d, "X.Tests/UnitTesting.json", '{"Bus": "amqps://user:secretpw@mq.example.co/vhost"}')
        self.assertEqual(self.kinds(), {"X.Tests/X.Tests.csproj": "refused"})

    def test_bin_obj_ignored(self):
        write(self.d, "U.Tests/U.Tests.csproj", TEST_SDK % "")
        write(self.d, "U.Tests/bin/Release/appsettings.json", '{"Db": "Host=db.example.co;Password=s3cr3tvalue"}')
        write(self.d, "U.Tests/obj/x/X.csproj", TEST_SDK % "")
        self.assertEqual(self.kinds(), {"U.Tests/U.Tests.csproj": "unit"})

    def test_directory_build_props_test_project(self):
        write(self.d, "tests/Directory.Build.props",
              '<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.10.0" /></ItemGroup></Project>')
        write(self.d, "tests/Real.Tests/Real.Tests.csproj", '<Project Sdk="Microsoft.NET.Sdk"></Project>')
        write(self.d, "tests/Real.Tests/appsettings.json", '{"Db": "Host=db.example.co;Password=x"}')
        write(self.d, "src/Api/Api.csproj", '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>')
        self.assertEqual(self.kinds(), {"tests/Real.Tests/Real.Tests.csproj": "refused", "src/Api/Api.csproj": None})

    def test_directory_build_targets_adds_testcontainers(self):
        write(self.d, "Directory.Build.targets",
              '<Project><ItemGroup Condition="\'$(IsTestProject)\' == \'true\'"><PackageReference Include="Testcontainers" Version="4.16.0" /></ItemGroup></Project>')
        write(self.d, "I.Tests/I.Tests.csproj", TEST_SDK % "")
        self.assertEqual(self.kinds(), {"I.Tests/I.Tests.csproj": "integration"})

    def test_non_test_project_has_no_kind(self):
        write(self.d, "Api/Api.csproj", '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>')
        self.assertEqual(self.kinds(), {"Api/Api.csproj": None})

    def test_cli_kind_lists_absolute_paths(self):
        write(self.d, "U.Tests/U.Tests.csproj", TEST_SDK % "")
        write(self.d, "I.Tests/I.Tests.csproj", TEST_SDK % ref("Testcontainers.PostgreSql"))
        out = io.StringIO()
        with redirect_stderr(io.StringIO()):
            import contextlib
            with contextlib.redirect_stdout(out):
                c.main(["--dir", self.d, "--kind", "integration"])
        self.assertEqual(out.getvalue().splitlines(), [os.path.realpath(os.path.join(self.d, "I.Tests/I.Tests.csproj"))])


if __name__ == "__main__":
    unittest.main()
