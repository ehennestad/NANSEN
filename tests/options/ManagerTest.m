classdef ManagerTest < matlab.unittest.TestCase
%ManagerTest Tests for nansen.options.Manager (profiles and resolution)

    properties
        Schema
        Manager
        Folder (1,1) string
    end

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, "code"), IncludingSubfolders=true))
        end
    end

    methods (TestMethodSetup)
        function createManager(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = fixture.Folder;
            testCase.Schema = createTestSchema("1.0.0");
            testCase.Manager = nansen.options.Manager(testCase.Schema, Location=testCase.Folder);
        end
    end

    methods (Test)

        function testDefaultsAndPresets(testCase)
            m = testCase.Manager;
            testCase.verifyEqual(m.ProfileNames, ["Defaults", "Fast"])
            testCase.verifyEqual(m.DefaultProfileName, "Defaults")
            testCase.verifyEqual(m.resolve(), testCase.Schema.getDefaults())
            testCase.verifyEqual(m.resolve("Fast").Preprocessing.binSize, 10)
        end

        function testCreateProfileStoresOnlyDifferences(testCase)
            m = testCase.Manager;

            % Give complete values: only differences from parent are stored
            values = m.resolve("Fast");
            values.threshold = 0.7;
            profile = m.createProfile("My profile", values, Parent="Fast", ...
                Description="Test profile", Tags=["test", "example"]);

            testCase.verifyEqual(profile.Overrides, struct("threshold", 0.7))
            testCase.verifyEqual(profile.SchemaVersion, "1.0.0")
            testCase.verifyTrue(isfile(fullfile(testCase.Folder, "test.method", "My_profile.json")))

            loaded = m.getProfile("My profile");
            testCase.verifyEqual(loaded.Tags, ["test", "example"])
            testCase.verifyEqual(loaded.Parent, "Fast")
            testCase.verifyFalse(isnat(loaded.Created))

            opts = m.resolve("My profile");
            testCase.verifyEqual(opts.Preprocessing.binSize, 10)
            testCase.verifyEqual(opts.threshold, 0.7)
        end

        function testReservedAndDuplicateNames(testCase)
            m = testCase.Manager;
            testCase.verifyError(@() m.createProfile("Defaults"), "NANSEN:Options:ReservedName")
            testCase.verifyError(@() m.createProfile("Fast"), "NANSEN:Options:ReservedName")
            testCase.verifyError(@() m.createProfile("bad/name"), "NANSEN:Options:InvalidName")

            m.createProfile("Mine", {"threshold", 0.1})
            testCase.verifyError(@() m.createProfile("Mine"), "NANSEN:Options:ProfileExists")
            m.createProfile("Mine", {"threshold", 0.2}, Overwrite=true)
            testCase.verifyEqual(m.resolve("Mine").threshold, 0.2)
        end

        function testRuntimeOverridesAndRecord(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.7}, Parent="Fast")

            [opts, record] = m.resolve("Mine", Overrides={"numWorkers", 2});
            testCase.verifyEqual(opts.Run.numWorkers, 2)

            testCase.verifyEqual(record.ProfileName, "Mine")
            testCase.verifyEqual(record.getSource("Preprocessing.method"), "defaults")
            testCase.verifyEqual(record.getSource("Preprocessing.binSize"), "preset:Fast")
            testCase.verifyEqual(record.getSource("threshold"), "profile:Mine")
            testCase.verifyEqual(record.getSource("Run.numWorkers"), "runtime")
            testCase.verifyNotEmpty(record.Hash)
            testCase.verifyClass(record.Provenance, "nansen.options.Provenance")

            % Transient runtime changes do not change the hash
            [~, record2] = m.resolve("Mine", CaptureProvenance=false);
            testCase.verifyTrue(record.isEquivalent(record2))
            testCase.verifyEmpty(record2.Provenance)

            % Records can be saved as plain structs and restored
            S = record.toStruct();
            testCase.verifyClass(S.Provenance, "struct")
            restored = nansen.options.OptionsRecord.fromStruct(S);
            testCase.verifyEqual(restored.Values, record.Values)
            testCase.verifyEqual(restored.Hash, record.Hash)
        end

        function testRuntimeOverridesAsStruct(testCase)
            opts = testCase.Manager.resolve("Defaults", ...
                Overrides=struct("Preprocessing", struct("binSize", 3)));
            testCase.verifyEqual(opts.Preprocessing.binSize, 3)

            testCase.verifyError(@() testCase.Manager.resolve("Defaults", ...
                Overrides={"binSize", -1}), "NANSEN:Options:InvalidValue")
        end

        function testRecordJsonRoundTrip(testCase)
            [~, record] = testCase.Manager.resolve("Fast");
            filePath = fullfile(testCase.Folder, "record.json");
            record.writeJson(filePath)

            restored = nansen.options.OptionsRecord.readJson(filePath);
            
            % Text is read from JSON as char. The schema restores the class
            testCase.verifyEqual(testCase.Schema.conform(restored.Values), record.Values)
            testCase.verifyEqual(testCase.Schema.computeHash(restored.Values), record.Hash)
            testCase.verifyEqual(restored.Hash, record.Hash)
            testCase.verifyEqual(string(restored.Provenance.Nansen.Commit), ...
                string(record.Provenance.Nansen.Commit))
            testCase.verifyLessThanOrEqual(abs(restored.Created - record.Created), seconds(1))
        end

        function testDefaultProfile(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.1})
            m.setDefaultProfile("Mine")
            testCase.verifyEqual(m.DefaultProfileName, "Mine")
            testCase.verifyEqual(m.resolve().threshold, 0.1)

            m.deleteProfile("Mine")
            testCase.verifyEqual(m.DefaultProfileName, "Defaults")
        end

        function testCannotDeleteParentOrPresets(testCase)
            m = testCase.Manager;
            m.createProfile("Parent", {"threshold", 0.1})
            m.createProfile("Child", {"method", "max"}, Parent="Parent")
            testCase.verifyError(@() m.deleteProfile("Parent"), "NANSEN:Options:ProfileInUse")
            testCase.verifyError(@() m.deleteProfile("Fast"), "NANSEN:Options:ReadOnlyProfile")

            opts = m.resolve("Child");
            testCase.verifyEqual(opts.threshold, 0.1)
            testCase.verifyEqual(opts.Preprocessing.method, "max")
        end

        function testRenameProfile(testCase)
            m = testCase.Manager;
            m.createProfile("Parent", {"threshold", 0.1})
            m.createProfile("Child", {"method", "max"}, Parent="Parent")
            m.setDefaultProfile("Parent")

            m.renameProfile("Parent", "Renamed")

            testCase.verifyEqual(m.UserProfileNames, ["Child", "Renamed"])
            testCase.verifyEqual(m.getProfile("Child").Parent, "Renamed")
            testCase.verifyEqual(m.DefaultProfileName, "Renamed")
            testCase.verifyEqual(m.resolve("Child").threshold, 0.1)
        end

        function testCyclicParentsAreRejected(testCase)
            m = testCase.Manager;
            m.createProfile("A", {"threshold", 0.1})
            m.createProfile("B", Parent="A")
            testCase.verifyError(@() m.updateProfile("A", Parent="B"), ...
                "NANSEN:Options:CyclicProfiles")
        end

        function testUpdateProfile(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.1}, Description="Old")

            m.updateProfile("Mine", {"binSize", 7}, Description="New")
            profile = m.getProfile("Mine");
            testCase.verifyEqual(profile.Description, "New")
            testCase.verifyEqual(profile.OverrideNames, ["Preprocessing.binSize", "threshold"])

            % Setting a value back to the parent value removes the override
            m.updateProfile("Mine", {"threshold", 0.5})
            testCase.verifyEqual(m.getProfile("Mine").OverrideNames, "Preprocessing.binSize")
        end

        function testWarningWhenInheritedDefaultsChange(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.7})

            testCase.Schema.setDefault("Preprocessing.method", "max")
            testCase.verifyWarning(@() m.resolve("Mine"), ...
                "NANSEN:Options:InheritedValuesChanged")

            m.refreshProfile("Mine")
            testCase.verifyWarningFree(@() m.resolve("Mine"))
            testCase.verifyEqual(m.resolve("Mine").Preprocessing.method, "max")
        end

        function testFrozenProfileKeepsValues(testCase)
            m = testCase.Manager;
            m.createProfile("Frozen", {"threshold", 0.7}, Frozen=true)

            testCase.Schema.setDefault("Preprocessing.binSize", 8)
            testCase.verifyEqual(m.resolve("Frozen").Preprocessing.binSize, 5)

            % A new parameter gets its default value
            testCase.Schema.addParameter("newParameter", 1)
            testCase.verifyEqual(m.resolve("Frozen").newParameter, 1)
        end

        function testProfileIsMigrated(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.7})

            % New version of schema, where threshold moved into a group
            schemaV2 = createTestSchema("2.0.0", ThresholdName="Detection.threshold");
            schemaV2.addMigration("1.0.0", "2.0.0", @(S) nansen.options.migrate.renameField( ...
                S, "threshold", "Detection.threshold"), Description="Moved threshold")

            m2 = nansen.options.Manager(schemaV2, Location=testCase.Folder);
            [opts, record] = m2.resolve("Mine");
            testCase.verifyEqual(opts.Detection.threshold, 0.7)
            testCase.verifyNotEmpty(record.MigrationLog)

            m2.refreshProfile("Mine")
            testCase.verifyEqual(m2.getProfile("Mine").SchemaVersion, "2.0.0")
        end

        function testObsoleteParametersAreIgnored(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.7})
            testCase.Schema.removeParameter("threshold")
            testCase.verifyWarning(@() m.resolve("Mine"), "NANSEN:Options:ObsoleteParameter")
        end

        function testCompareProfiles(testCase)
            differences = testCase.Manager.compareProfiles("Defaults", "Fast");
            testCase.verifyEqual(differences.Name, "Preprocessing.binSize")
            testCase.verifyEqual(differences.ValueB, {10})
        end

        function testListProfiles(testCase)
            m = testCase.Manager;
            m.createProfile("Mine", {"threshold", 0.1}, Parent="Fast")
            T = m.listProfiles();
            testCase.verifyEqual(T.Name', ["Defaults", "Fast", "Mine"])
            testCase.verifyEqual(string(T.Type)', ["Defaults", "Preset", "User"])
            testCase.verifyEqual(T.Parent', ["", "Defaults", "Fast"])
            testCase.verifyEqual(T.IsDefault', [true, false, false])
        end

        function testExportAndImportProfile(testCase)
            m = testCase.Manager;
            m.createProfile("Parent", {"threshold", 0.1})
            m.createProfile("Child", {"method", "max"}, Parent="Parent")

            filePath = fullfile(testCase.Folder, "exported.json");
            m.exportProfile("Child", filePath)

            % Import into another location (e.g. another user)
            otherFixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            other = nansen.options.Manager(testCase.Schema, Location=otherFixture.Folder);
            other.importProfile(filePath, Name="Shared")

            testCase.verifyEqual(other.resolve("Shared"), m.resolve("Child"))
        end

        function testImportLegacyOptions(testCase)
            m = testCase.Manager;

            % Create a file in the format of nansen.manage.OptionsManager
            opts = nansen.options.legacy.toEditorStruct(testCase.Schema);
            opts.threshold = 0.3;
            OptionsEntries = struct("Name", {'Preset Options', 'Legacy'}, ...
                "Type", {'Preset', 'Custom'}, "Description", {'', ''}, ...
                "Options", {testCase.Schema.getDefaults(), opts}, ...
                "DateCreatedNum", {0, 0}, "DateCreated", {'', ''});
            DefaultOptionsName = 'Legacy';
            filePath = fullfile(testCase.Folder, "legacy.mat");
            save(filePath, "OptionsEntries", "DefaultOptionsName")

            imported = m.importLegacyOptions(filePath);
            testCase.verifyEqual(imported, "Legacy")
            testCase.verifyEqual(m.resolve("Legacy").threshold, 0.3)
            testCase.verifyEqual(m.DefaultProfileName, "Legacy")
        end
    end
end

function schema = createTestSchema(version, options)
    arguments
        version (1,1) string
        options.ThresholdName (1,1) string = "threshold"
    end
    schema = nansen.options.Schema("test.method", Version=version);
    schema.addParameter("Preprocessing.binSize", 5, Min=1, Integer=true)
    schema.addParameter("Preprocessing.method", "mean", Choices={"mean", "max"})
    schema.addParameter("Run.numWorkers", 4, Transient=true)
    schema.addParameter(options.ThresholdName, 0.5)
    schema.addPreset("Fast", {"binSize", 10}, Description="Heavy binning")
end
