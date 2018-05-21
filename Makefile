

# the 'tcc' trick is from here: https://stackoverflow.com/questions/2167393/vala-gotchas-tips-and-tricks

grabini: Downloader.vala Segment.vala Speedometer.vala Utils.vala Debug.vala Main.vala
	CC=tcc valac -o grabini --pkg libsoup-2.4 $^
