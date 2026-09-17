# mrog-input proof run — 2026-09-04T12:46:37-05:00 — SID:LINUX-D8H

## State before
```
lease file : none
panic file : none
log        : -rw-r----- 1 chris adm 0 Sep  4 08:47 /var/log/mrog/input/events.jsonl
```

## 1. Mutating verbs with NO lease — must all REFUSE
```
mrog-input move 900 500    -> mrog-input: REFUSED (no-lease)
mrog-input click 1         -> mrog-input: REFUSED (no-lease)
mrog-input type hello      -> mrog-input: REFUSED (no-lease)
mrog-input key ctrl+s      -> mrog-input: REFUSED (no-lease)
mrog-input moveclick 900 500 1 -> mrog-input: REFUSED (no-lease)
```

## 2. Read-only verbs — must WORK without any lease (Level 0)
```
mrog-input where           -> 1708 362
mrog-input window          -> Navigator,firefox	Claude Code — Mozilla Firefox
mrog-input status          -> no input lease events used: 0 / 400 
```

## 3. Screenshot — Level 0, no lease needed
```
mrog-input shot -> /home/USER/Pictures/mrog-20260904-124650.png
  file: 632495 bytes
```

## 4. Kill switch — no password, and it must block everything after
```
mrog-input: input halted - revoked by hand
input halted. To clear it and start again:
mrog-input move 900 500    -> mrog-input: REFUSED (panic)
mrog-input where           -> 1290 479
  (read-only still works while halted, by design)
```

## 5. The record — both copies
```
-- events.jsonl --
  File "<string>", line 6
    print(f"{d[\"ts\"]}  {d[\"result\"]:<22} {d[\"verb\"]:<10} {d.get(\"detail\",\"\")[:28]:<28} {d.get(\"class\",\"\")[:20]}")
                ^
SyntaxError: unexpected character after line continuation character
(no events yet)

-- journald (the copy chris cannot quietly edit) --
Sep 04 12:46:37 laptop mrog-input[36309]: REFUSED:no-lease verb=click sid=none detail=btn1 class= title=
Sep 04 12:46:37 laptop mrog-input[36315]: REFUSED:no-lease verb=type sid=none detail=hello class= title=
Sep 04 12:46:37 laptop mrog-input[36321]: REFUSED:no-lease verb=key sid=none detail=ctrl+s class= title=
Sep 04 12:46:37 laptop mrog-input[36327]: REFUSED:no-lease verb=moveclick sid=none detail=900,500 btn1 class= title=
Sep 04 12:46:50 laptop mrog-input[36443]: OK verb=shot sid=none detail=/home/USER/Pictures/mrog-20260904-124650.png class= title=
Sep 04 12:46:50 laptop mrog-input[36450]: PANIC TRIPPED reason=revoked by hand sid=none
Sep 04 12:46:50 laptop mrog-input[36453]: REVOKED verb=revoke sid=none detail= class= title=
Sep 04 12:46:50 laptop mrog-input[36459]: REFUSED:panic verb=move sid=none detail=900,500 class= title=
```

## 6. Two defects found by running it
```
A. mrog-input audit was BROKEN - SyntaxError, hidden by 2>/dev/null.
   Escaped double quotes inside an f-string inside a single-quoted shell
   string. Fixed in ~/mrog/input/mrog-input; needs one root install.
   The fixed parser, run against the live log:

B. mrog-input shot still wrote to ~/Pictures, not the new Documents tree.
   Fixed to ~/Documents/mrog/Screenshots (MROG_SHOTDIR overrides).
```

## 7. A weakness worth naming: the kill switch is user-removable
```
panic present : yes
after plain rm : GONE - an agent running as chris can clear it
mrog-input move 900 500 -> mrog-input: REFUSED (no-lease)

So the halt is a convenience brake, not a boundary - consistent with the
advisory model Chris accepted, but it should not be mistaken for more.
```

## Not run - needs Chris's password
```
  sudo mrog-input-lease grant 5 --scope click --note "proving it"
then:  mrog-input moveclick 960 600   -> should WORK
       mrog-input type hello          -> REFUSED (scope-is-click-need-type)
       focus a terminal, mrog-input click -> REFUSED (denied-class)
```
END

## 6A — CORRECTION: the first fix was also wrong

The first attempt piped the log into `python3 - <<'EOF'`. That cannot work: **the heredoc IS
stdin**, so the pipe from `tail` is discarded and `sys.stdin` reads the program text. It printed
nothing and looked like an empty log. The working form passes the log path and count as
ARGUMENTS and opens the file in Python. Verified against the real log (9 rows rendered) and
against a missing file (`(no events yet)`, no traceback).

That is two wrong versions of the same six-line function, both of which *looked* fine until run.

# ============ BEHIND-THE-LEASE RUN — 2026-09-04T13:04:00-05:00 ============
```
0. armed:
     scope=click by=chris 233s left
     events used: 0 / 400
     safe window=0x05600006   terminal=0x05200006

1. GRANTED LEASE MUST PERMIT  (move only, no click)
   focused: kate,kate	scratch.txt 
   mrog-input move 2880 600 ->    pointer now: 2880 600

2. SCOPE IS SEPARATE  (lease is click-only, so type must refuse)
   mrog-input type hello -> mrog-input: REFUSED (scope-is-click-need-type)
   mrog-input key ctrl+s -> mrog-input: REFUSED (scope-is-click-need-type)

3. WINDOW DENYLIST  (focus a terminal, then click)
   focused: gnome-terminal-server,Gnome-terminal	user@laptop: ~
   mrog-input click -> mrog-input: REFUSED (denied-class)
```
```
4. HUMAN-MOTION ABORT  (pointer moves without us = a human is here)
   agent left the pointer at: 2880 600
   simulating a hand on the mouse -> moved it to 2400 700
   mrog-input move 2880 600 -> mrog-input: input halted - pointer moved 480x100px without us - a human is at the machine mrog-input: REFUSED (human-motion) 

5. AND IT STAYS DEAD  (panic latched, no password needed to stop)
   mrog-input move 2880 600 -> mrog-input: REFUSED (panic)
   mrog-input click        -> mrog-input: REFUSED (panic)
   mrog-input where        -> 2400 700
   (read-only still works while halted, by design)
```

## The record, both copies
```
2026-09-04T12:46:37-05:00  REFUSED:no-lease       moveclick  900,500 btn1                 
2026-09-04T12:46:50-05:00  OK                     shot       /home/USER/Pictures/mrog-20 
2026-09-04T12:46:50-05:00  REVOKED                revoke                                  
2026-09-04T12:46:50-05:00  REFUSED:panic          move       900,500                      
2026-09-04T12:48:14-05:00  REFUSED:no-lease       move       900,500                      
2026-09-04T13:04:01-05:00  OK                     move       2880,600                     kate,kate
2026-09-04T13:04:01-05:00  REFUSED:scope-is-click-need-type type       hello                        
2026-09-04T13:04:01-05:00  REFUSED:scope-is-click-need-type key        ctrl+s                       
2026-09-04T13:04:02-05:00  REFUSED:denied-class   click      btn1                         gnome-terminal-server,
2026-09-04T13:04:18-05:00  REFUSED:human-motion   move       2880,600                     
2026-09-04T13:04:18-05:00  REFUSED:panic          move       2880,600                     
2026-09-04T13:04:18-05:00  REFUSED:panic          click      btn1                         

Sep 04 12:48:14 mrog-input[36588]: REFUSED:no-lease verb=move sid=none detail=900,500 class= title=
Sep 04 13:02:54 mrog-input[37220]: LEASE GRANTED scope=click mins=5 by=chris note=proving it
Sep 04 13:04:01 mrog-input[37326]: OK verb=move sid=none detail=2880,600 class=kate,kate title=scratch.txt
Sep 04 13:04:01 mrog-input[37342]: REFUSED:scope-is-click-need-type verb=type sid=none detail=hello class= title=
Sep 04 13:04:01 mrog-input[37353]: REFUSED:scope-is-click-need-type verb=key sid=none detail=ctrl+s class= title=
Sep 04 13:04:02 mrog-input[37400]: REFUSED:denied-class verb=click sid=none detail=btn1 class=gnome-terminal-server,Gnome-terminal title=user@laptop: ~
Sep 04 13:04:18 mrog-input[37445]: PANIC TRIPPED reason=pointer moved 480x100px without us - a human is at the machine sid=none
Sep 04 13:04:18 mrog-input[37448]: REFUSED:human-motion verb=move sid=none detail=2880,600 class= title=
Sep 04 13:04:18 mrog-input[37454]: REFUSED:panic verb=move sid=none detail=2880,600 class= title=
Sep 04 13:04:18 mrog-input[37460]: REFUSED:panic verb=click sid=none detail=btn1 class= title=
```

## VERDICT — all six gates driven to fail on their own stated failure class
```
  1 panic file               REFUSED (panic)            proven
  2 live lease               REFUSED (no-lease)         proven
  3 scope                    REFUSED (scope-is-click-need-type)  proven
  4 budget + rate            not exercised (would need 400 events)
  5 human-motion             REFUSED (human-motion), panic latched   proven
  6 window denylist          REFUSED (denied-class) on gnome-terminal  proven

  granted lease PERMITS      move OK on kate, logged with class+title  proven
  read-only while halted     where/window still answer   proven
  record                     events.jsonl AND journald agree   proven
```

Resting state: panic latched, lease expires 13:07:54 by itself.
The next 'mrog-input-lease grant' clears the panic - no cleanup needed.
END OF PROOF RUN

=== state now ===
INPUT HALTED (panic file present)
scope=click by=chris 192s left
events used: 1 / 400
panic: latched
