Grabini
=======

An HTTP downloader.

Features
========

- Downloads a file in multiply segments simultaneously.

- All the state is recorded clearly in an .ini file you can edit.

- Lets you circumvent the speed limit of some free filesharing servers by
  skipping a HEAD request needed to find out the file size (you the `--estimate`
  option to enable this), and thus starting all segments at once, sometimes
  not giving the server a chance to enforce the "one HTTP connection policy".
