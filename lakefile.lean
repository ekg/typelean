import Lake
open Lake DSL

package "typelean" where
  version := v!"0.1.0"

lean_lib «Typelean» where
  -- add library configuration options here

@[default_target]
lean_exe "typelean" where
  root := `Main
