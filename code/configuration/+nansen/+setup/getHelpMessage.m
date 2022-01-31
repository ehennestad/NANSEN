function msg = getHelpMessage(keyword)


switch keyword
    
% % Data location page

    case 'Data location type'
        msg = {...
            'This is a name to describe the data location type.\n', ...
            '\nIt could for example be Rawdata or Processed.', ...
            'If raw data is saved in multiple locations, you can', ...
            'add multiple entries, for example, Rawdata_imaging', ...
            'and Rawdata_behavior'
            };

    case 'Data location root directory'
        msg = 'Browse to locate a root directory of the data location type (A root directory should contain a set of data folders).';
    
    case 'Set backup'
        msg = {...
            'Select the secondary button to add a backup location.',...
            'This is useful if you keep data in multiple locations', ...
            '(Not implemented yet).' ...
            };
        
    case 'Permission'
        msg = {...
            'Select data permission mode for data location. Use Read for', ...
            'data locations containing raw data and Write for data', ...
            'locations containing processed data. This setting', ...
            'can be used to ensure that raw data is not modified' ...
            };
        
        
% % Folder organization page

    case 'Select subfolder example'
        
        msg = {'Select a subfolder from the list to use as an example', ...
            'for the folder hierarchy which your data is organized after.'};
        
    case 'Set subfolder type'
        msg = {'Choose which type the selected subfolder is'};

    case 'Exclusion list'
        msg = {'Enter a word or a comma-separated list of words to ignore.\n', ...
            '\nAll folders containing one or more words in this list', ...
            'will be excluded from the list of detected folders.\n', ...
            '\nNote: Each input row corresponds to a subfolder level'};
        
    case 'Inclusion list'
        msg = {'Enter a word/expression to only include folders matching', ...
            'that word/expression.\n', ...
            '\nThe expression can contain the wildcard (*) character,'...
            'and the # symbol can be used to substitute numbers. See', ...
            'matlab''s regexp function for a complete overview of valid', ...
            'expressions.\n', ...
            '\nExample: If a folder is named "session_123_training"', ...
            'the expression could be session_###. In that case, only', ...
            'folders containing the word session followed by three numbers', ...
            ' will be included in the detected folder list.'};
        
% % Metadata page
    case 'Variable name'
        msg = 'The variable name of the metadata variable';
        
    case 'Select foldername'
        msg = {'Select a folder that contains the value of the', ...
            'metadata variable in the name'};
    
    case 'Select string'
        msg = {'Select the letter positions that contain the substring', ...
            'for the corresponding variable.\n', ...
            '\nNote: If letters are in variable positions or the', ...
            'substrings are of variable length, use the advanced options.'};
        
    case 'Selection mode'
        msg = {'Select mode for identifying substring.\n', ...
            '\nSelect "ind" to enter the location of letters (e.g 20:end)', ...
            'or "expr" to enter a regular expression (see doc for ', ...
            'matlab''s regexp for possible expressions to enter).'};
        
    case 'Input'
        msg = {'Advanced only: Enter a list of numbers if the mode is set to "ind" or', ...
             'a regular expression if mode is set to "expr". A list of', ...
             'numbers should be formatted the same way as when indexing', ...
             'an array or a string on the matlab command line (i.e 5:10)', ...
             'as getting letters from a while the regular expression is', ...
             'anything that can be used by the regexp function'};


    case 'Result'
        msg = 'The resulting text based on selection from previous columns';

        
% % Variable page

    case 'Data variable name'
        msg = {'A variable name of data used in this pipeline. Some', ...
        'variables are predefined and the variable names should not be', ...
        'changed. You can also add your own variables.'};
        
    case 'Filename expression'
        msg = {'A static subpart of the filename for files containing', ...
            'data of this variable type. Will be used by the software to', ...
            'automatically detect data. \nUse the eye next to the data', ...
            'location dropdown to open a session folder.'};
    
    case 'Data location'
        msg = {'Select the data location where this variable is found', ...
            'or should be saved'};
        
    case 'File type'
        msg = {'Select which filetype this file is'};
        
    case 'File adapter'
        msg = {'Select which file adapter should \n be used when loading', ...
            'data from or opening this file'};

    otherwise
        msg = 'No help available yet';
end

if isa(msg, 'cell')
    msg = strjoin(msg, ' ');
end

msg = sprintf(msg);


end

