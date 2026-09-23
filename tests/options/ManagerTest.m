classdef ManagerTest < matlab.unittest.TestCase
%ManagerTest Tests for nansen.options.Manager (profiles and resolution)

    properties
        Schema
        Manager
        Folder
    end

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, 'code'), 'IncludingSubfolders', true))
        end
    end

    methods (TestMethodSetup)
        function createManager(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = fixture.Folder;

            s = nansen.options.Schema('test.method', 'Version', '1.0.0');
            s.addParameter('Preprocessing.binSize', 5, 'Min', 1, 'Integer', true)
            s.addParameter('Preprocessing.method', 'mean', 'Choices', {'mean', 'max'})
            s.addParameter('Run.numWorkers', 4, 'Transient', true)
            s.addParameter('threshold', 0.5)
            s.addPreset('Fast', {'binSize', 10}, 'Heavy binning')

            testCase.Schema = s;
            testCase.Manager = nansen.options.Manager(s, 'Location', testCase.Folder);
        end
    end

    methods (Test)

        function testDefaultsAndPresets(testCase)
            m = testCase.Manager;
            testCase.verifyEqual(m.ProfileNames, {'Defaults', 'Fast'})
            testCase.verifyEqual(m.DefaultProfileName, 'Defaults')
            testCase.verifyEqual(m.resolve(), testCase.Schema.getDefaults())

            opts = m.resolve('Fast');
            testCase.verifyEqual(opts.Preprocessing.binSize, 10)
        end

        function testCreateProfileStoresOnlyDifferences(testCase)
            m = testCase.Manager;

            % Give complete values: only differences from parent are stored
            values = m.resolve('Fast');
            values.threshold = 0.7;
            profile = m.createProfile('Mine', values, 'Parent', 'Fast', ...
                'Description', 'Test profile');

            testCase.verifyEqual(profile.Overrides, struct('threshold', 0.7))
            testCase.verifyEqual(profile.SchemaVersion, '1.0.0')
            testCase.verifyTrue(isfile(fullfile(testCase.Folder, 'test.method', 'Mine.json')))

            opts = m.resolve('Mine');
            testCase.verifyEqual(opts.Preprocessing.binSize, 10)
            testCase.verifyEqual(opts.threshold, 0.7)
        end

        function testReservedAndDuplicateNames(testCase)
            m = testCase.Manager;
            testCase.verifyError(@() m.createProfile('Defaults', {}), 'NANSEN:Options:ReservedName')
            testCase.verifyError(@() m.createProfile('Fast', {}), 'NANSEN:Options:ReservedName')
            m.createProfile('Mine', {'threshold', 0.1})
            testCase.verifyError(@() m.createProfile('Mine', {}), 'NANSEN:Options:ProfileExists')
            m.createProfile('Mine', {'threshold', 0.2}, 'Overwrite', true)
            testCase.verifyEqual(m.resolve('Mine').threshold, 0.2)
        end

        function testRuntimeOverridesAndRecord(testCase)
            m = testCase.Manager;
            m.createProfile('Mine', {'threshold', 0.7}, 'Parent', 'Fast')

            [opts, record] = m.resolve('Mine', 'numWorkers', 2);
            testCase.verifyEqual(opts.Run.numWorkers, 2)

            testCase.verifyEqual(record.ProfileName, 'Mine')
            testCase.verifyEqual(record.getSource('Preprocessing.method'), 'defaults')
            testCase.verifyEqual(record.getSource('Preprocessing.binSize'), 'preset:Fast')
            testCase.verifyEqual(record.getSource('threshold'), 'profile:Mine')
            testCase.verifyEqual(record.getSource('Run.numWorkers'), 'runtime')
            testCase.verifyNotEmpty(record.Hash)
            testCase.verifyTrue(isfield(record.Provenance, 'Nansen'))

            % Transient runtime changes do not change the hash
            [~, record2] = m.resolve('Mine');
            testCase.verifyTrue(record.isEquivalent(record2))

            % Records can be saved as plain structs and restored
            restored = nansen.options.OptionsRecord.fromStruct(record.toStruct());
            testCase.verifyEqual(restored.Values, record.Values)
            testCase.verifyEqual(restored.Hash, record.Hash)
        end

        function testRecordJsonRoundTrip(testCase)
            [~, record] = testCase.Manager.resolve('Fast');
            filePath = fullfile(testCase.Folder, 'record.json');
            record.writeJson(filePath)
            restored = nansen.options.OptionsRecord.readJson(filePath);
            testCase.verifyEqual(restored.Values, record.Values)
            testCase.verifyEqual(restored.Hash, record.Hash)
        end

        function testDefaultProfile(testCase)
            m = testCase.Manager;
            m.createProfile('Mine', {'threshold', 0.1})
            m.setDefaultProfile('Mine')
            testCase.verifyEqual(m.DefaultProfileName, 'Mine')
            testCase.verifyEqual(m.resolve().threshold, 0.1)

            m.deleteProfile('Mine')
            testCase.verifyEqual(m.DefaultProfileName, 'Defaults')
        end

        function testCannotDeleteParentOrPresets(testCase)
            m = testCase.Manager;
            m.createProfile('Parent', {'threshold', 0.1})
            m.createProfile('Child', {'method', 'max'}, 'Parent', 'Parent')
            testCase.verifyError(@() m.deleteProfile('Parent'), 'NANSEN:Options:ProfileInUse')
            testCase.verifyError(@() m.deleteProfile('Fast'), 'NANSEN:Options:ReadOnlyProfile')

            opts = m.resolve('Child');
            testCase.verifyEqual(opts.threshold, 0.1)
            testCase.verifyEqual(opts.Preprocessing.method, 'max')
        end

        function testCyclicParentsAreRejected(testCase)
            m = testCase.Manager;
            m.createProfile('A', {'threshold', 0.1})
            m.createProfile('B', {}, 'Parent', 'A')
            testCase.verifyError(@() m.updateProfile('A', {}, 'Parent', 'B'), ...
                'NANSEN:Options:CyclicProfiles')
        end

        function testWarningWhenInheritedDefaultsChange(testCase)
            m = testCase.Manager;
            m.createProfile('Mine', {'threshold', 0.7})

            testCase.Schema.setDefault('Preprocessing.method', 'max')
            testCase.verifyWarning(@() m.resolve('Mine'), ...
                'NANSEN:Options:InheritedValuesChanged')

            m.refreshProfile('Mine')
            testCase.verifyWarningFree(@() m.resolve('Mine'))
            testCase.verifyEqual(m.resolve('Mine').Preprocessing.method, 'max')
        end

        function testFrozenProfileKeepsValues(testCase)
            m = testCase.Manager;
            m.createProfile('Frozen', {'threshold', 0.7}, 'Frozen', true)

            testCase.Schema.setDefault('Preprocessing.binSize', 8)
            opts = m.resolve('Frozen');
            testCase.verifyEqual(opts.Preprocessing.binSize, 5)

            % A new parameter gets its default value
            testCase.Schema.addParameter('newParameter', 1)
            opts = m.resolve('Frozen');
            testCase.verifyEqual(opts.newParameter, 1)
        end

        function testProfileIsMigrated(testCase)
            m = testCase.Manager;
            m.createProfile('Mine', {'threshold', 0.7})

            % New version of schema, where threshold moved into a group
            s = nansen.options.Schema('test.method', 'Version', '2.0.0');
            s.addParameter('Preprocessing.binSize', 5)
            s.addParameter('Preprocessing.method', 'mean', 'Choices', {'mean', 'max'})
            s.addParameter('Run.numWorkers', 4, 'Transient', true)
            s.addParameter('Detection.threshold', 0.5)
            s.addMigration('1.0.0', '2.0.0', @(S) nansen.options.migrate.renameField( ...
                S, 'threshold', 'Detection.threshold'), 'Moved threshold')

            m2 = nansen.options.Manager(s, 'Location', testCase.Folder);
            [opts, record] = m2.resolve('Mine');
            testCase.verifyEqual(opts.Detection.threshold, 0.7)
            testCase.verifyNotEmpty(record.MigrationLog)

            m2.refreshProfile('Mine')
            testCase.verifyEqual(m2.getProfile('Mine').SchemaVersion, '2.0.0')
        end

        function testObsoleteParametersAreIgnored(testCase)
            m = testCase.Manager;
            m.createProfile('Mine', {'threshold', 0.7})
            testCase.Schema.removeParameter('threshold')
            testCase.verifyWarning(@() m.resolve('Mine'), 'NANSEN:Options:ObsoleteParameter')
        end

        function testCompareProfiles(testCase)
            m = testCase.Manager;
            differences = m.compareProfiles('Defaults', 'Fast');
            testCase.verifyEqual({differences.Name}, {'Preprocessing.binSize'})
        end

        function testListProfiles(testCase)
            m = testCase.Manager;
            m.createProfile('Mine', {'threshold', 0.1}, 'Parent', 'Fast')
            T = m.listProfiles();
            testCase.verifyEqual(T.Name', {'Defaults', 'Fast', 'Mine'})
            testCase.verifyEqual(T.Type', {'defaults', 'preset', 'user'})
        end

        function testImportLegacyOptions(testCase)
            m = testCase.Manager;

            % Create a file in the format of nansen.manage.OptionsManager
            opts = testCase.Schema.getDefaults();
            opts.threshold = 0.3;
            opts.Preprocessing.method_ = {'mean', 'max'}; % config field
            OptionsEntries = struct('Name', {'Preset Options', 'Legacy'}, ...
                'Type', {'Preset', 'Custom'}, 'Description', {'', ''}, ...
                'Options', {testCase.Schema.getDefaults(), opts}, ...
                'DateCreatedNum', {now, now}, 'DateCreated', {'', ''}); %#ok<TNOW1>
            DefaultOptionsName = 'Legacy';
            filePath = fullfile(testCase.Folder, 'legacy.mat');
            save(filePath, 'OptionsEntries', 'DefaultOptionsName')

            imported = m.importLegacyOptions(filePath);
            testCase.verifyEqual(imported, {'Legacy'})
            testCase.verifyEqual(m.resolve('Legacy').threshold, 0.3)
            testCase.verifyEqual(m.DefaultProfileName, 'Legacy')
        end
    end
end
