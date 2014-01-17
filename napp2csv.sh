#!/bin/bash
##
## napp2csv.sh -- a shell script to process data files received from
## NAPP (North American Population Project) into CSVs.
##
## Copyright by Eric Nystrom, distributed under the terms of the MIT License.
##   April 2012--January 2014.
##
#################
## FILE FORMAT ##
#################
##
## The NAPP data files are composed of lines of fixed-length fields,
## with no field separators.  The fields are defined by a command
## file, available in SPSS, SAS, or STATA, that specifies what ranges
## (also what lengths) the fields are, and in what order.  The command
## file also specifies the English translation of most of the
## variables, which are numeric in the data.  These variable maps
## could later be substituted into the .csv we are producing, but
## instead for space and consistency the will be made into related
## tables of their own in a database and consulted when necessary via
## well-crafted queries.

## Use the .sas file to give us the list of variables and ranges,
## massaging the data with sed and other utilities until we get what
## we need.  

while getopts ":ac:d:ikorsz" opt; do
   case $opt in
    a)
	## Add the variable names as a header in the finished CSV files
	echo "Will add the variable name headers to all finished files"
	ADDHEADERS=YES
	;;
    c)
	## Use alternate command file, specified
	command=$OPTARG
	echo "Using alternate command file: $OPTARG"
	;;
    d)
	## Use alternate data file, specified 
	origdata=$OPTARG
	echo "Using alternate datafile: $OPTARG"
	;;
    i)
	## Make a file to create indexes on all columns of "data" and
	## the "id" column of each subsidiary table
	echo "Will generate indexes"
	INDEX="YES"
	;;
    k)
	## Save the cutscript after run
	echo "Will save the cutscript file after running"
	SAVECUTSCRIPT=YES
	;;
    o)
	## Overwrite existing .csv and .txt files
	echo "Will overwrite existing .csv and .txt files"
	OVERWRITECSV=YES
	;;
    r)
	## Don't actually run the cutscript
	RUNCUTSCRIPT=NO
	echo "Will not run the finished cutscript"
	;;
    s)
	## Save the scrubbed data file
	echo "Will save the scrubbed data file after running cutscript"
	SAVESCRUBBED=YES
	;;
    z)
	## Don't squeeze extra spaces out of the final file
	SQUEEZE=NO
	echo "Will not squeeze extra spaces"
        ;;
    \?)
        echo "Invalid option: -$OPTARG" 
        exit 1
        ;;
    :)
	echo "Option -$OPTARG requires an argument." >&2
	exit 1
	;;
   esac
done
## Need this to clear off the options, so $1 is as it should be, etc.
shift $(($OPTIND - 1)) 

## Check for empty command line; have to do this after the getops stuff
if [ "a$1" = "a" ]
then
  echo "Usage:  $( basename $0 ) [ options ] basefilename"
  echo " "
  echo "Options:"
  echo "  -a           : Add variable name headers to finished CSV files"
  echo "  -c filename  : Specify alternate command file (include extension)"
  echo "  -d filename  : Specify alternate data file (include extension)"
  echo "  -i           : Create index-generating file: BASEFILENAME.idx"
  echo "  -k           : Keep the cutscript file after run"
  echo "  -o           : Overwrite existing .csv/.txt files if necessary (CAREFUL!)"
  echo "  -r           : Do not run the cutscript we produce"
  echo "  -s           : Save the scrubbed data file after run"
  echo "  -z           : Do not squeeze the extra spaces out of the final CSV"
  exit 2
fi

## Set the name variable, to be used in a moment
name=$1

## If $command not set through getopts, set it now as default
if [ "a$command" = "a" ]
then
  command=$name.sas  
fi

## If $origdata not set through getopts, set it now as default
if [ "a$origdata" = "a" ]
then
  origdata=$name.dat
fi

## Now check that these files exist
if [ ! -f $command ] 
then
  echo "Command file $command does not exist!"
  exit 2
fi

if [ ! -f $origdata ] 
then
  echo "Data file $datafile does not exist!"
  exit 2
fi

## Set name of data file with temp number, this will be scrubbed and
## used throughout
datafile=$$-$origdata

#################################
## PREP DATA FILE STRIP DELIMS ##
#################################

## Need to strip delimiter characters, but must replace with some
## other character otherwise fields get screwed up.  The first is
## colon, because we plan to use that for our delimiter, the second is
## replacing all double-quotes because they cause issues in the SQL
## output and single-quotes can be escaped more easily.
tr ':' '.' < $origdata > $origdata-tmp
tr '"' "'" < $origdata-tmp > $datafile
rm $origdata-tmp

##################################
## GET FIELDS FROM COMMAND FILE ##
##################################
## Eventually I could change/add on these statements to produce
## properly formatted .sql files to feed into mysql or similar.  For
## the likely future, however, I am happy using "csv2sqlite" to
## convert them to .sql (originally csv2sql; tiny mod by EN to produce
## non-typed table columns, which sqlite can handle easily)

######################
## Variables/Ranges ##
######################
## use sed to print range of lines between lines that start with input
## and the end of that statement, indicated by semicolon; squeeze out
## extra spaces; delete extra space at beginning of line; exclude the
## "input" and ";" lines, also deleting newlines.  Input is filename
## of .sas file; output is a file named to add variables and ranges.

## Unless overwrite is on, check for existing file and bail if found
if [[ "$OVERWRITECSV" != "YES" ]] 
then
    if [[ -e "$name-varranges.txt" ]] 
    then
	echo "Existing file $name-varranges.txt; aborting"
	exit 2
    fi
fi

sed -n '
	/^input/,/^\;/ {
	     s/\$//
             s/ \+/ /g
             s/^ *//g
             /^input/ d
             /^\;/ d
	     /^$/ d
	     p
	}
' "$command" > "$name-varranges.txt"

#####################
## Variable Labels ##
#####################
## use sed to find the "variable labels" section of the .sas file, and
## use a procedure to grab it and save it separately.  This section is
## enclosed by a line that begins (and only contains) the text
## "variable labels" and is ended by a period, by itself, on a line.

## Unless overwrite is on, check for existing file and bail if found
if [[ "$OVERWRITECSV" != "YES" ]] 
then
    if [[ -e "$name-varlabels.txt" ]]
    then
	echo "Existing file $name-varlabels.txt; aborting"
	exit 2
    fi
fi

sed -n '
	/^label/,/^\;$/ {
             s/=//
             s/ \+/ /g
             s/^ *//g
             /^label/ d
             /^\;$/ d
	     /^$/ d
	     p
	}
' "$command" > "$name-varlabels.txt"

####################################
## Variables with existing values ##
####################################

## So each of the variable labels in the .sas file basically opens a
## section where the translations between the numeric values and a
## text value are stored.

## Figured out I could grep for the unique string that begins the
## section, use sed to transform it and chop it up (have to strip a
## trailing "_f" and also watch out for an occasional "$" in between
## the "value" and variable name. (Hence the funky range address) Don't
## forget to use double-quotes in the sed command below so variable
## expansion can take place; also had to escape the underscore.  Can
## add additional statements below, for example to strip the
## double-quoted strings in the output files.  Right now I'm going to
## strip quotes and substitute a colon in there so everything uses the
## same delimiter.
##
## update -- added a little header, changed the output to a .csv file
## named for the variable, in the current directory, hardcoded colon delim.

for label in $( grep "^value " "$command" | 
            sed -e 's/^value //' -e 's/_f$//' -e 's/\$ //' ) 
do 

  ## Unless overwrite is on, check for existing file and bail if found
  if [[ "$OVERWRITECSV" != "YES" ]]
  then
      if [[ -e "$label.csv" ]]
      then
          echo "Existing file $label.csv; aborting"
          exit 2
      fi
  fi

  ## Adding the little header to each of these files as they are made
  if [[ "$ADDHEADERS" == "YES" ]] 
  then
      echo "id:desc" > "$label.csv"
  fi

  ## Grab the value pairs
  sed -n "
	/^value[\$ ]* $label\_f/,/\;/ {
             s/\:/\,/g  # any colons to commas so we can use : for delim
             s/ = /\:/ # use equal sign as handy marker for delimiter
             s/\"//g # strip double-quotes
             s/ \+/ /g # compress whitespace
             s/^ *//g # remove leading whitespace
             /^value[\$ ]* $label\_f/ d # remove initial range line
             /^\;/ d # remove end-of-range line
	     p
	}
  " "$command" >> "$label.csv"

  ## Make $name.idx entries if desired
  if [[ "$INDEX" == "YES" ]]
  then
      echo "CREATE INDEX IF NOT EXISTS idx_id_$label ON $label(id);" >> "$name.idx"
  fi

done

#######################
## CREATE CSV HEADER ##
#######################
## Use the -VR file to create a header for our forthcoming data.
## Here, I'm hardcoding the delimiter, as elsewhere, but may want to
## change that.  Pipeline below cuts the variable name from the -varranges
## field, uses tr to get everything on one line, separated by
## delimiter (colon), then uses sed to strip the last trailing colon
## and replace it with a newline, so this file can stand alone as a
## header file. MAKING IT .TXT so doesn't get swept up in .csv globbing

## Unless overwrite is on, check for existing file and bail if found
if [[ "$OVERWRITECSV" != "YES" ]]
then
    if [[ -e "$name-header.txt" ]]
    then
	echo "Existing file $name-header.txt; aborting"
	exit 2
    fi
fi

cut -d' ' -f1 "$name-varranges.txt" | tr '\n' ':' | sed 's/:$/\n/' > "$name-header.txt"

#############################
## CREATE SCRIPT FOR "CUT" ##
#############################
## Now, use a similar idea as the -VR to create a little script to run
## cut, to slice the data file into the appropriate ranges.  No need
## to check for overwriting because the cutscript has a temporary name
## (w/ PID)

printf "cut --output-delimiter=':' -c " > cutscript-$$

## now what I want is a list of the ranges, with a comma and slash at
## the end of each.  Then delete "$", remove beginning whitespace,
## remove all characters that are not whitespace that preceed
## whitespace (this removes the variable names without disturbing the
## ranges -- had to do it this way because earlier version looked for
## A-Z and choked on variable names that had mixed letters/numbers),
## then compress whitespace, add comma and slash to end of line, then
## delete the final line and any blank lines.
sed -n '
	/^input/,/^\;/ {
	     s/\$//
             s/[^\s]* / /
             s/ \+/ /g
             s/^ *//g
             s/$/,\\/
             /^input/ d
             /^\;/ d
	     /^$/ d
	     p
	}
' "$command" >> cutscript-$$

## Now use sed to remove the comma from the last line of the script,
## because there's not an obvious (to me) way of addressing that line
## in the range above.  Use -i to edit file in place as well.
sed -i '$s/,//' cutscript-$$

## Now add the name of the input data file to the cutscript at the
## end, note the needed leading space
echo " \"$datafile\"" >> cutscript-$$

## Make it executable
chmod +x cutscript-$$

## Tell us the name
echo "cutscript is:  cutscript-$$"

if [[ "$RUNCUTSCRIPT" = "NO" ]]
then
    echo "Skipping the running of the cutscript as directed"
    echo "Run manually like so: ./cutscript-$$ > $name.csv"
    exit 0
fi

## Check for existing file, then run the cutscript
## Unless overwrite is on, bail if existing file found
if [[ "$OVERWRITECSV" != "YES" ]]
then
    if [[ -e "$name.csv" ]]
    then
	echo "Existing file $name.csv; aborting"
	exit 2
    fi
fi

./cutscript-$$ > "$name.csv"

## Optional: Add the header to the CSV. Left off by default because
## having the header in the file will only be useful for smaller
## datasets

if [[ "$ADDHEADERS" == "YES" ]]
then
    #echo "Adding header to main .CSV file"
    cat "$name-header.txt" "$name.csv" > tmp-$$.csv
    mv tmp-$$.csv "$name.csv"
fi

#####################################
## Optional: Finish the Index file ##
#####################################

if [[ "$INDEX" == "YES" ]]
then
    ## Use the VR file for column names in the main (data) database.
    for i in `cut -d' ' -f1 "$name-varranges.txt"`
    do
	echo "CREATE INDEX IF NOT EXISTS idx_$i ON data($i);" >> "$name.idx"
    done
fi

##############
## CLEAN UP ##
##############

## Save or delete the scrubbed data
if [[ "$SAVESCRUBBED" == "YES" ]]
then
    echo "Saved scrubbed data file as: $datafile"
else
    rm "$datafile"
fi

## Squeeze (or not) the whitespace in the completed file. Default is
## to do it since it's a lot of empty space. This isn't a perfect
## optimization, as the first one will leave one trailing space on
## those large fixed-length fields, but the second one takes care of
## that, or should.

if [[ "$SQUEEZE" == "NO" ]]
then
    echo "Not squeezing space in final .csv"
else
    echo "Squeezing extra space..."
    tr -s ' ' < "$name.csv" > "squeeze-$name-$$.csv"
    sed -i 's/ :/:/g' "squeeze-$name-$$.csv"
    mv "squeeze-$name-$$.csv" "$name.csv"
fi

## Save or delete the cutscript ( -k on command line to "keep" it)
if [[ "$SAVECUTSCRIPT" == "YES" ]]
then
    echo "Saving cutscript file after run"
else
    echo "Deleting cutscript"
    rm ./cutscript-$$
fi

