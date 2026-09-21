# Switchboard

A command center for the web services running on your Mac, on
[Droppy](https://getdroppy.app)'s shelf and menu bar. A Droplet built with
[DroppyKit](https://getdroppy.app/docs/droppykit).

## Two halves, on purpose

**Switchboard (this repo)** is the droplet. It declares `network-client` and
`menu-bar` and nothing else. It reads portless's own route table off disk,
probes each route for liveness, and draws the list.

**[switchboard-agent](https://github.com/crockalet/switchboard-agent)** is a separate CLI you install
yourself. It owns the config that names commands and launchd labels, and it is
the only half that ever runs one.

The split is not incidental. A droplet is native code inside Droppy's process
with no sandbox between the two, so it *can* spawn anything — but the capability
list has no exec entry, and review diffs declared capabilities against the
symbols a bundle links. A droplet whose purpose is running user-supplied
commands has nothing honest to declare itself as. Keeping the commands in a
separate binary is what makes this one publishable.

## Read only, with nothing installed

Install the droplet alone and it still works. `~/.portless/routes.json` gives
every named `.localhost` service, its port, and the pid of anything portless
launched; `kill(pid, 0)` and a loopback connect turn that into live status. No
capability covers a file read, none is needed, and `~/.portless` is outside
every TCC-protected location.

What you do not get is control: knowing a route exists is not knowing how to
restart what is behind it. Those rows show an open button and nothing else.

## With the companion

Install `switchboard-agent` and describe your services once. Rows it knows gain
start, stop and restart. A service that needs its own flags —
`baguette serve --allowed-hosts sim.localhost` — is described in the agent's
config, and Switchboard just shows it.

When both halves describe the same port, the companion's row wins, because it is
the one that can act, and it inherits the portless URL.

## Surfaces

| Surface | What it shows |
| --- | --- |
| Shelf widget | Up to four services, status and port, controls when they exist |
| Menu bar extra | The full list, with a submenu per service |
| Settings pane | Companion status, port and refresh interval |

## Developing

With the [DroppyKit](https://gitlab.com/droppyformac1/droppykit) scripts on your
`PATH`:

```bash
droppykit run       # open it in the development harness
droppykit build     # produce .build/Switchboard.droplet
droppykit validate  # the checks a submission runs
```

Drop `.build/Switchboard.droplet` on
[Droppy Playground](https://getdroppy.app/download/playground) to try it on the
real notch.

## Before submitting

The scaffold's placeholder icon and creator avatar are still in place, and
`creator` and `source` in `droplet.json` still say `Your name` and
`github.com/you`. Replace all four.

## Licence

MIT.
