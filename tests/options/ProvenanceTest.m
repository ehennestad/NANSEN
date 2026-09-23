classdef ProvenanceTest < matlab.unittest.TestCase
%ProvenanceTest Tests for nansen.options.Provenance

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, 'code'), 'IncludingSubfolders', true))
        end
    end

    methods (Test)
        function testCapture(testCase)
            S = nansen.options.Provenance.capture( ...
                'MethodName', 'nansen.options.Schema', 'IncludeToolboxes', false);

            testCase.verifyEqual(S.Nansen.Version, nansen.version())
            testCase.verifyNotEmpty(S.Matlab.Version)
            testCase.verifyNotEmpty(S.Timestamp)
            testCase.verifyNotEmpty(S.Method.FileHash)
            testCase.verifyTrue(isstruct(S.Dependencies))

            % When run from a git clone, the commit is recorded
            rootPath = nansen.options.Provenance.getNansenRootPath();
            if isfolder(fullfile(rootPath, '.git'))
                testCase.verifyMatches(S.Nansen.Commit, '^[0-9a-f]{40}$')
            end
        end

        function testGitInfoWithoutRepository(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            folder = fixture.Folder;
            info = nansen.options.internal.getGitInfo(folder);
            testCase.verifyEmpty(info.Commit)
        end

        function testGitInfoPackedRefs(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            folder = fixture.Folder;
            gitDir = fullfile(folder, '.git');
            mkdir(gitDir)
            writeText(fullfile(gitDir, 'HEAD'), sprintf('ref: refs/heads/main\n'))
            commit = repmat('a', 1, 40);
            writeText(fullfile(gitDir, 'packed-refs'), ...
                sprintf('# pack-refs\n%s refs/heads/main\n', commit))
            writeText(fullfile(gitDir, 'config'), sprintf( ...
                '[remote "origin"]\n\turl = https://user:secret@github.com/org/repo.git\n'))

            subFolder = fullfile(folder, 'sub');
            mkdir(subFolder)
            info = nansen.options.internal.getGitInfo(subFolder);

            testCase.verifyEqual(info.Commit, commit)
            testCase.verifyEqual(info.Branch, 'main')
            % Credentials are removed from the remote url
            testCase.verifyEqual(info.RemoteUrl, 'https://github.com/org/repo.git')
        end
    end
end

function writeText(filePath, text)
    fid = fopen(filePath, 'w');
    fprintf(fid, '%s', text);
    fclose(fid);
end
