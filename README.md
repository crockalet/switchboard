# Switchboard

A command center for the web services running on your Mac, on
[Droppy](https://getdroppy.app)'s shelf and menu bar. A Droplet built with
[DroppyKit](https://getdroppy.app/docs/droppykit).

## Two halves, on purpose

**Switchboard (this repo)** is the droplet. It declares `network-client`,
`menu-bar`, `hud` and `expanded-surface`, and nothing else. It reads portless's
own route table off disk, probes each route for liveness, and draws the list.

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

While an action settles, its row shows progress instead of a control that is
already stale. When it fails, the row says why in yellow for a few seconds. With
the shelf closed the notch answers too: a confirmation is a HUD strip, a refusal
grows into a card carrying what launchd actually said.

## Logs

Press the log button on any companion row in the menu bar panel and the tail
takes over the notch.

Nothing needs configuring. A launchd job's log path comes from `StandardOutPath`
in its own plist; a supervised command writes to one the agent gave it. Only a
service that logs somewhere neither default finds needs `logPath` set.

The tail polls while the surface is up and stops the moment it closes, so
nothing reads a file for an audience that is not there.

## Surfaces

| Surface | What it shows |
| --- | --- |
| Shelf widget | Up to four services, status and port, controls when they exist |
| Menu bar extra | The full list, each row with its own open, log and lifecycle buttons |
| Settings pane | Companion status, port and refresh interval, in Droppy's native form |
| HUD | The result of a start, stop or restart |
| Expanded surface | A live tail of one service's log |

Paired, the widget keeps the status dot, the name and the open button, and drops
the lifecycle controls the width cannot hold.

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

## A note on `droppykit validate`

It warns that "makeExpanded carries a Button". That check greps a file for
`makeExpanded` and for `Button` and warns when one file has both; it is aimed at
a live activity's unmounted card. Switchboard does not provide a live activity
at all. The strings co-occurred because `makeExpandedSurfaceView` — an *expanded
surface* requirement, which Droppy does mount — sat in the same file as the log
surface's Close button. Splitting the view into `LogSurfaceView.swift` silences
it.

## Licence

MIT.
