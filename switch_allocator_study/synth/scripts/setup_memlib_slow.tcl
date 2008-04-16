# ----------------------------------------------------------------------
#
#  File: setup_memlib_slow.tcl
#
# ----------------------------------------------------------------------

set mem_dir ../mem

# ----
#  Append memory models to the link library
# --
append link_library { RF2SH_W16_B32_slow.db }
append search_path { ../mem/RF2SH }

