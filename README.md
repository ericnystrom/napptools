# napptools

Manipulate census microdata from the North Atlantic Population Project (IPUMS)

By Eric Nystrom (eric.nystrom@rit.edu), distributed under the terms of
the MIT License.

Last revision: January 17, 2014

## Purpose

**Purpose:** To convert fixed-width census microdata data files from
  the North Atlantic Population Project (NAPP) (http://nappdata.org) into
  .CSV files, and then to load those into a SQLite database. The tools
  may also be generally useful for converting fixed-width data that is
  described in a SAS-compatible command file.

**Note:** I am not in any way affiliated with NAPP or the Minnesota
  Population Center, and do not speak for them in any way. I am just a
  satisfied user of their products.

## Contents

`napptools` consists of three script programs:

- `napp2csv.sh`: A Bash script that uses traditional unix tools `cut`,
  `sed`, and `tr` to chop a NAPP data file into its respective
  columns, guided by a SAS-format command file. This also creates
  secondary tables in .CSV format from the variable descriptions in
  the SAS file.

- `csv2sqlite`: A public-domain AWK program written by Lorance Stinson
  (available from http://lorance.freeshell.org/csvutils/) to convert
  .CSV files into a series of SQL statements that load the data into a
  database. Two small changes were made by Eric Nystrom to Stinson's
  original code to fix a bug and better fit the output to SQLite's
  capabilities by specifying non-typed columns.

- `nappbuild.sh`: A Bash script to employ `napp2csv.sh` and
  `csv2sqlite` to create .CSV and .SQL files, then load them into a
  SQLite database. 

## Usage

1. Get an account at http://nappdata.org, receive access approval, and
   select your desired variables.  Download the fixed-width text data file
   itself, which will end in a `.dat.gz` extension, as well as a
   command file in SAS format.
2. Ensure all dependencies are met. On most Linux systems the only one
   you may need to install will be `sqlite3`, the command-line client
   for the SQLite database package.
3. Run `nappbuild.sh` in the directory containing your data file and
   your command file, passing the name of the SQLite database you wish
   to create.
   - If your data file is `napp_00001.dat.gz` and your command file is
     `napp_00001.sas` then run `nappbuild.sh` like so:
   - `nappbuild.sh -i -n napp_00001 -d MyNAPPData.db`
4. From there, you can use your database from the SQLite command shell
   `sqlite3` or your favorite programming language.

## Structure

For databases created with `napptools`, most of the NAPP data ends up
in a single large table, called `data`.  Each of the columns in `data`
is named for the NAPP field, such as `SERIAL`, `PERWT`, `NAMELAST`,
etc.  (Since SQLite's column names are not case-sensitive, lower case
works fine too.)

Some of these columns have self-contained information, such as
`NAMELAST` or `OCCSTRNG`, but others contain a numeric code that will
typically need to be translated into human-readable
values. Translations for these codes were offered by NAPP in the
command file.  The `napptools` suite breaks those translations out of
the command file, into separate tables loaded into the SQLite
database.  These secondary tables are named for the NAPP variable, and
always contain two columns, `id` and `desc`.  With this information,
it is easy to use a SQL JOIN command to bring the translations into
your results, or you can refer to the codes directly if desired.

For example, to show the number of people listed in each category of
the `race` variable in the state of New Mexico (`stateus` value of
35):

	SELECT race.desc, count(*)
	FROM data
	JOIN race ON data.race = race.id
	WHERE stateus = 35
	GROUP BY race.desc

## Caveats

- The SQLite index generation routine is rather crude, as it makes an
  index for every column in the `data` table and the `id` column in
  all secondary tables.  This is likely overkill, but there's no doubt
  column indexes on at least some of the columns helps many queries.
- This was designed and used on a Debian Linux system. It seems likely
  that it will be portable to similar unix-based systems as long as
  the dependencies are all met, but YMMV.
