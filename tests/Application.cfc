component {
	this.name = "cbtoon Test Suite";

	this.mappings[ "/tests"  ] = ExpandPath( "/" );
	this.mappings[ "/testbox" ] = ExpandPath( "/testbox" );
	this.mappings[ "/cbtoon"  ] = ExpandPath( "../" );

	setting requesttimeout=60000;
}
