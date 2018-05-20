# [WIP] Cachet

`cachet` is for mnesia headaches.

##  Preamble

Having a mnesia database starting to become too big for your available memory ?

- For `ram_copies` and `disc_copies`, the entire table is kept in memory, so data size is limited by available RAM. 
- For `disc_only_copies`, tables are limited to 2 GB each due to `dets` backend.

`cachet` will plug in your mnesia database and work by listening events on your database.
Your main application feeding database do not have to be rewritten.
Your clients using database may need some code change in order to call `cachet` API instead `mnesia` one (simply replace module name in code in some case).
`cachet` will dispatch requests either in RAM tables or DISC tables. 


## Usage

`cachet` can be used to address below issues :

- mnesia database with to many `disc_copies` tables to be kept in memory.
- mnesia database with some few data needing quick access and many data to be kept with slower access.

`cachet` propose two modes : 

- `cache` : cache last used data in memory.
- `split` : split newer data in memory (copy on disc) and older on disc only.

## Modes

### Cache

Last used data kept in memory and all data on disc.
Table in RAM can be `ram_only` (volatile) or `disc_copy` (persistent)
Table on Disc must be `disc_only_copy`

Event handler when Cache RAM table under records/size limit :

            user                    cachet
1. Write in RAM table   -> Copy record in DISC table
2. Write in DISC table  -> Copy record in RAM table
3. Delete in RAM table  -> Delete in DISC table
4. Delete in DISC table -> Delete in RAM table

Event handler when Cache RAM table over records/size limit :

            user                    cachet
1. Write in RAM table   -> Copy in DISC table + Delete older in RAM table
2. Write in DISC table  -> Copy in RAM table and Delete older 
3. Delete in RAM table  -> Delete in DISC table
4. Delete in DISC table -> Delete in RAM table

### Split

Separating data with quick access on active data and slow access to unactive data.
Table in RAM  must be `disc_copy` (persistent)
Table on Disc must be `disc_only_copy`

Event handler when RAM table under records/size limit
RAM table does not reach records/size limit :

         user                    cachet
1. Write in RAM table   -> Do nothing
2. Write in DISC table  -> Do nothing
3. Delete in RAM table  -> Do nothing
4. Delete in DISC table -> Do nothing

Event handler when RAM table over records/size limit
RAM table reached records/size limit :

         user                    cachet
1. Write in RAM table   -> Move older record in DISC table
2. Write in DISC table  -> Do nothing
3. Delete in RAM table  -> Do nothing
4. Delete in DISC table -> Do nothing

## Configuration

{tables, [{'RamTable', 'DiscTable', {'Column', Method}, Mode, Options}, ...]}.

'RamTable' : Atom name of RAM table

'DiscTable' : Atom name of Disc table

'Column' : Atom name of column to analyze

'Method' : [id|timestamp|term] Atom name of method to use for data separation

Mode : [cache|split] Mode to use on table

Options : [{k, V}, ...] Options for mode used.

### Options

Options = [{key, Value}, ...]

Where key can be :

- `records` , where value :
   - if < 1 : percent of records in disc table (may increase at each start !)
   - if > 1 : number of records.
   - if < 0 : difference between number of records in disc table and this value.
              Max integer on 32bit is 134217728, let's use it as default.

- `memory` , where value :
   - if < 1 : percentage of current memory usable by emulator
   - if > 1 : memory in bytes
   - if < 0 : difference between memory usable by emulator and this value.





