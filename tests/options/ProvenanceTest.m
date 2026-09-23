classdef ProvenanceTest < matlab.unittest.TestCase
%ProvenanceTest Tests for nansen.options.Provenance and git information

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, "code"), IncludingSubfolders=true))
        end
    end

    methods (Test)
        function testCapture(testCase)
            p = nansen.options.Provenance.capture( ...
                MethodName="nansen.options.Schema", IncludeToolboxes=false);

            testCase.verifyEqual(p.Nansen.Version, string(nansen.version()))
            testCase.verifyNotEmpty(p.Matlab.Version)
            testCase.verifyFalse(isnat(p.Timestamp))
            testCase.verifyMatches(p.Method.FileHash, "^[0-9a-f]{64}$")

            % When run from a git clone, the commit is recorded
            rootPath = nansen.options.Provenance.getNansenRootPath();
            if isfolder(fullfile(rootPath, ".git"))
                testCase.verifyMatches(p.Nansen.Commit, "^[0-9a-f]{40}$")
            end

            restored = nansen.options.Provenance.fromStruct(p.toStruct());
            testCase.verifyEqual(restored.Nansen, p.Nansen)
        end

        function testSha256(testCase)
            testCase.verifyEqual(nansen.options.internal.sha256("abc"), ...
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            % Non-ASCII text is hashed as UTF-8
            testCase.verifyEqual(nansen.options.internal.sha256("æøå"), ...
                nansen.options.internal.sha256(unicode2native('æøå', 'UTF-8')))
        end

        function testGitInfoWithoutRepository(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            info = nansen.options.internal.getGitInfo(fixture.Folder);
            testCase.verifyEqual(info.Commit, "")
        end

        function testGitInfoPackedRefs(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            gitDir = fullfile(fixture.Folder, ".git");
            mkdir(gitDir)
            writelines("ref: refs/heads/main", fullfile(gitDir, "HEAD"))
            commit = string(repmat('a', 1, 40));
            writelines(["# pack-refs"; commit + " refs/heads/main"], ...
                fullfile(gitDir, "packed-refs"))
            writelines(["[remote ""origin""]"; ...
                "	url = https://user:secret@github.com/org/repo.git"], ...
                fullfile(gitDir, "config"))

            subFolder = fullfile(fixture.Folder, "sub");
            mkdir(subFolder)
            info = nansen.options.internal.getGitInfo(subFolder);

            testCase.verifyEqual(info.Commit, commit)
            testCase.verifyEqual(info.Branch, "main")
            % Credentials are removed from the remote url
            testCase.verifyEqual(info.RemoteUrl, "https://github.com/org/repo.git")
        end
    end
end
