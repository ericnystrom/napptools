#!/bin/bash
##
## nappbuild.sh: Build a sqlite database from a NAPP sample.
##
## Copyright by Eric Nystrom, distributed under the terms of the MIT License.
##   July 2012--January 2014.
##
## Last revision: January 17, 2014
##
## Usage:
##
##   buildnapp.sh [ -i ] -n NAPPNAME -d DATABASENAME.db
##
## Output:
##   - NAPPNAME.dat will be split into its constituent data and tables
##   - .csv files for the main data (data.csv) and all related tables will be created
##   - A .sql file will be created for each .csv, containing statements to 
##     insert the information into the database
##   - All these will be actually loaded into DATABASENAME.db, which is a 
##     SQLite database
##   - If the -i option is used, an index will be created for each column in 
##     the "data" table and each "id" column in the other tables

##########################
## Command line options ##
##########################
while getopts "d:in:" opt; do
    case $opt in
	d)
	    ## Provide database name.  This should not exist, or else
	    ## it will get clobbered.  Include extension.
	    dbname=$OPTARG
	    ;;
	i)
	    ## Create and use indexes?
	    INDEX="YES"
	    ;;
	n)
	    ## The base name of the NAPP files (both the SAS-format
	    ## command file and the Data file).  As downloaded, this
	    ## would be something like "napp_00001" but it can be
	    ## changed to anything as long as both files match for
	    ## this part.
	    napp=$OPTARG
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

## Print usage if no command line options
if [ "a$1" = "a" ]
then
  echo "Usage:  $( basename $0 ) [ -i ] -n NAPPNAME -d DATABASE.db"
  echo " "
  echo "Options:"
  echo "  -n NAPPNAME    : Base name of NAPP files (i.e. napp_00001)"
  echo "  -d DATABASE.db : Name of database to create"
  echo "  -i             : Optional: load index for each column in \"data\" table"
  echo "                 :   and \"id\" column for every other table"
  exit 2
fi

#####################################
## Test for files and dependencies ##
#####################################
## Check dependency on "sqlite3" (part of "sqlite3" package in Debian)
if ! which sqlite3 &>/dev/null; then
    echo "Missing dependency, aborting: sqlite3"
    exit 4
fi

## Check dependency on "csv2sqlite" (part of EN's napptools)
if ! which napp2csv.sh &>/dev/null; then
    echo "Missing dependency, aborting: napp2csv.sh"
    exit 4
fi

## Check dependency on "csv2sqlite" (part of EN's napptools)
if ! which csv2sqlite &>/dev/null; then
    echo "Missing dependency, aborting: csv2sqlite"
    exit 4
fi

## test for $napp.dat.gz and $napp.sas in current directory
if [[ ! -e "$napp.dat.gz" ]]
then
    echo "File $napp.dat.gz not found in current directory, aborting"
    exit 3
fi

if [[ ! -e "$napp.sas" ]]
then
    echo "File $napp.sas not found in current directory, aborting"
    exit 3
fi

#######################
## Process the files ##
#######################

echo "Unpacking $napp.dat.gz..."
gunzip "$napp.dat.gz"

echo "Running napp2csv..."
if [[ "$INDEX" == "YES" ]]
then
    napp2csv.sh -a -i "$napp"
else
    napp2csv.sh -a "$napp"
fi
mv "$napp.csv" "data.csv"

## Generate all the SQL
echo "Running csv2sqlite..."
for i in *.csv
do 
   echo "   Working on $i" 
   if [[ "$i" == "data.csv" ]] ; then
       # Will copy the csv2sqlite statement b/c I want to clobber existing .sql otherwise
       # Add header in case of data.sql
       echo "PRAGMA synchronous=OFF;" > data.sql
       csv2sqlite -c -s ':' -t `basename $i .csv` -E "'" $i >> `basename $i .csv`.sql  
   else
       csv2sqlite -c -s ':' -t `basename $i .csv` -E "'" $i > `basename $i .csv`.sql  
   fi
   echo "   Finished with $i" 
done

## Load the database
echo "Loading sqlite database: $dbname..."
for i in *.sql
do 
   echo "   Working on $i" 
   echo ".read $i" | sqlite3 "$dbname"
   if [[ $? -ne 0 ]]
   then
       echo "SQLite exited with status: $? while processing $i"
       exit 1
   fi
done

## Load the index-creation file, if specified
if [[ "$INDEX" == "YES" ]]
then
    echo "  Loading indexes..."
    echo ".read $napp.idx" | sqlite3 "$dbname"
   if [[ $? -ne 0 ]]
   then
       echo "SQLite exited with status: $? while processing $napp.idx"
       exit 1
   fi
fi

echo "Complete."
