# Portal Trace 0.3 (diagnostics)

Changes nothing. Records every map load the game asks for: the map you were
on, the target and entry, how many times the request repeated, and the game
code that made it. At the next statue save it writes them all as one
`PORTALTRACE` line to the log (as a script error, which also switches it off
for the session).

Use: go through the portal you want traced, come back, save at a statue.

0.2 also records every distinct trigger event the game runs, in order: the
map, which command it is (its code address) and its arguments. Walk up to a
portal, wait for its prompt, press A, come back and save: the line then holds
the portal's whole command sequence.

0.3 records each event's command name and its real arguments (0.2 read them
from the wrong place).
