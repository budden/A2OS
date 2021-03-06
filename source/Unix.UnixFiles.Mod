(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE UnixFiles;   (** AUTHOR "gf"; PURPOSE "Unix file systems" *)

(*  derived fron (SPARCOberon) Files.Mod by J. Templ 1.12. 89/14.05.93 *)

IMPORT S := SYSTEM, Unix, Kernel, Modules, Log := KernelLog, Files, Commands;


CONST
	NBufs = 4;  Bufsize = 4096;  NoDesc = -1;

	Open = 0;  Create = 1;  Closed = 2;	(* file states *)

	NoKey = -1;
	CreateFlags = Unix.rdwr + Unix.creat + Unix.trunc;

	TraceCollection = 0;
	Trace = {};
	Separator = 0AX;
VAR
	tempno: INTEGER;
	openfiles: LONGINT;

	searchPath: ARRAY 1024 OF CHAR;
	cwd: ARRAY 256 OF CHAR;

	unixFS: UnixFileSystem; (* must be unique *)
	collection: Collection; (* must be unique *)

TYPE
	Filename = ARRAY 256 OF CHAR;

	NameSet = OBJECT
			VAR
				name: ARRAY 64 OF CHAR;
				left, right: NameSet;

				PROCEDURE Add( CONST filename: ARRAY OF CHAR ): BOOLEAN;
					(* add filename if it not already exists. else return false *)
				BEGIN
					IF filename = name THEN  RETURN FALSE  END;
					IF filename < name THEN
						IF left = NIL THEN  NEW( left, filename );  RETURN TRUE
						ELSE  RETURN left.Add( filename )
						END
					ELSE
						IF right = NIL THEN  NEW( right, filename );  RETURN TRUE
						ELSE  RETURN right.Add( filename )
						END
					END
				END Add;

				PROCEDURE & Init( CONST filename: ARRAY OF CHAR );
				BEGIN
					COPY( filename, name );
					left := NIL; right := NIL
				END Init;

			END NameSet;

	AliasFileSystem = OBJECT (Files.FileSystem)
		VAR
			fs: UnixFileSystem;

			PROCEDURE & Init*( realFS: UnixFileSystem);
			BEGIN
				SELF.fs := realFS;
			END Init;

			PROCEDURE New0( name: ARRAY OF CHAR ): Files.File;
			VAR f: Files.File;
			BEGIN
				f := fs.New0( name );
				IF f # NIL THEN  f.fs := SELF  END;
				RETURN f;
			END New0;

			PROCEDURE Old0( name: ARRAY OF CHAR ): Files.File;
			VAR f: Files.File;
			BEGIN
				f :=  fs.Old0( name );
				IF f # NIL THEN  f.fs := SELF  END;
				RETURN f;
			END Old0;

			PROCEDURE Delete0( name: ARRAY OF CHAR;  VAR key: LONGINT; VAR res: WORD );
			BEGIN
				fs.Delete0( name, key, res );
			END Delete0;

			PROCEDURE Rename0( old, new: ARRAY OF CHAR;  fold: Files.File;  VAR res: WORD );
			BEGIN
				fs.Rename0( old, new, fold, res );
			END Rename0;

			PROCEDURE Enumerate0( mask: ARRAY OF CHAR;  flags: SET;  enum: Files.Enumerator );
			BEGIN
				fs.Enumerate0( mask, flags, enum );
			END Enumerate0;

			PROCEDURE FileKey( name: ARRAY OF CHAR ): LONGINT;
			VAR
			BEGIN
				RETURN fs.FileKey( name );
			END FileKey;

			PROCEDURE CreateDirectory0( name: ARRAY OF CHAR;  VAR res: WORD );
			BEGIN
				fs.CreateDirectory0( name, res );
			END CreateDirectory0;

			PROCEDURE RemoveDirectory0( name: ARRAY OF CHAR;  force: BOOLEAN;  VAR key: LONGINT; VAR res: WORD );
			BEGIN
				fs.RemoveDirectory0( name, force, key, res );
			END RemoveDirectory0;

			PROCEDURE Has(CONST name: ARRAY OF CHAR; VAR fullName: ARRAY OF CHAR; VAR flags: SET): BOOLEAN;
			BEGIN
				RETURN fs.Has(name, fullName, flags);
			END Has;

	END AliasFileSystem;

	SearchByFstat = OBJECT
	VAR
		found: File;
		stat: Unix.Status;

		PROCEDURE Init( s: Unix.Status );
		BEGIN
			found := NIL;
			stat := s;
		END Init;

		PROCEDURE EnumFile( f: ANY;  VAR cont: BOOLEAN );
		BEGIN
			WITH f: File DO
				IF (stat.ino = f.ino) & (stat.dev = f.dev) THEN
					(* possible different name but same file! *)
					ResetBuffers( f, stat );
					found := f; cont := FALSE;
				END;
			END;
		END EnumFile;

	END SearchByFstat;




	Collection = OBJECT  (* methods in Collection shared by objects Filesystem and File *)
	VAR oldFiles, newFiles: Kernel.FinalizedCollection;
		ssearch: SearchByFstat;

		PROCEDURE & Init*;
		BEGIN
			NEW( oldFiles );  NEW( newFiles );   NEW( ssearch );
		END Init;

		PROCEDURE AddNew( F: File );
		BEGIN {EXCLUSIVE}
			IF TraceCollection IN Trace THEN Log.String( "Collections.AddNew: " );  Log.String( F.workName );  Log.Ln;  END;
			newFiles.Add( F, FinalizeFile );
		END AddNew;

		PROCEDURE AddOld( F: File );
		BEGIN {EXCLUSIVE}
			IF TraceCollection IN Trace THEN Log.String( "Collections.AddOld: " );  Log.String( F.workName );  Log.Ln;  END;
			oldFiles.Add( F, FinalizeFile );
		END AddOld;

		PROCEDURE ByStat(CONST stat: Unix.Status): File;
		BEGIN{EXCLUSIVE}
			ssearch.Init(stat);
			oldFiles.EnumerateN(ssearch.EnumFile);
			IF ssearch.found = NIL THEN
				newFiles.EnumerateN(ssearch.EnumFile)
			END;

			IF TraceCollection IN Trace THEN
				Log.String( "Collections.ByStatus: " );  Log.Ln;
				IF ssearch.found = NIL THEN Log.String("not found") ELSE Log.String("found") END;
			END;

			RETURN ssearch.found;
		END ByStat;

		PROCEDURE Finalize;
		BEGIN {EXCLUSIVE}
			IF TraceCollection IN Trace THEN Log.String( "Collections.Finalize " );  Log.Ln;  END;
			newFiles.Enumerate( EnumFinalize );  newFiles.Clear();
			oldFiles.Enumerate( EnumFinalize );  oldFiles.Clear();
		END Finalize;

		PROCEDURE FinalizeFile( obj: ANY );
		VAR F: File;
		BEGIN
			F := obj( File );
			IF TraceCollection IN Trace THEN Log.String( "Collections.FinalizeFile " );  Log.String( F.workName );  Log.Ln;  END;
			F.Finalize()
		END FinalizeFile;

	END Collection;


	UnixFileSystem* = OBJECT (Files.FileSystem)

				PROCEDURE & Init;
				BEGIN
					prefix := "";  vol := NIL;  desc := "UnixFS"
				END Init;


				PROCEDURE New0*( name: ARRAY OF CHAR ): Files.File;
				VAR f: File; stat: Unix.Status;
					  res, err: LONGINT;
					  path, nameonly: ARRAY 512 OF CHAR;
				BEGIN {EXCLUSIVE}
					(*first check if the path actually exits first using fstat. fstat returns -1 and sets erno to ENOENT when a component of the path doesn't exist or the entire path is empty*)
					Files.SplitPath( name, path, nameonly );
					res:=Unix.stat( ADDRESSOF( path ), stat ) ;
					err:=Unix.errno();
					IF (name="") OR (path="") OR (res>=0) OR (err#Unix.ENOENT) THEN
						NEW( f, SELF );
						f.workName := "";  COPY( name, f.registerName );
						f.fd := NoDesc;  f.state := Create;  f.fsize := 0;  f.fpos := 0;
						f.swapper := -1;   (*all f.buf[i] = NIL*)
						f.key := NoKey;  f.fs := SELF;
						f.tempFile := name = "";
						RETURN f;
					ELSE
						Log.String( "UnixFileSystem.New0: file allocation failed. Probably a nonexistent path." );  Log.Ln;
						RETURN NIL;
					END;
				END New0;


				PROCEDURE IsDirectory( VAR stat: Unix.Status ): BOOLEAN;
				VAR mode: LONGINT;
				BEGIN
					mode := stat.mode;
					RETURN ODD( mode DIV 4000H )
				END IsDirectory;


				PROCEDURE Old0*( name: ARRAY OF CHAR ): Files.File;
				VAR f: File;  stat: Unix.Status;  fd, r, pos: LONGINT;
					oflags: SET32;  nextdir, path: Filename;
				BEGIN  {EXCLUSIVE}
					IF name = "" THEN  RETURN NIL  END;

					IF IsFullName( name ) THEN
						COPY( name, path );  nextdir := "";
					ELSE
						pos := 0;  ScanPath( pos, nextdir );  MakePath( nextdir, name, path );
						ScanPath( pos, nextdir )
					END;

					LOOP
						f := NIL;
						r := Unix.access( ADDRESSOF( path ), Unix.R_OK );
						IF r >= 0 THEN
							r := Unix.access( ADDRESSOF( path ), Unix.W_OK );
							IF r < 0 THEN  oflags := Unix.rdonly  ELSE  oflags := Unix.rdwr  END;
							fd := UnixOpen( ADDRESSOF( path ), oflags, 0 );
							IF fd >= 0 THEN
								r := Unix.fstat( fd, stat );
								f := collection.ByStat(stat);
								IF f # NIL THEN
									(* use the file already cached *)  r := Unix.close( fd );  EXIT
								ELSE
									NEW( f, SELF );
									f.fd := fd;  f.dev := stat.dev;  f.ino := stat.ino;
									f.mtime := stat.mtime.sec;  f.fsize := stat.size;  f.fpos := 0;
									f.state := Open;  f.swapper := -1;   (*all f.buf[i] = NIL*)
									COPY( path, f.workName );  f.registerName := "";
									f.tempFile := FALSE;
									IF IsDirectory( stat ) THEN
										f.flags := {Files.Directory, Files.ReadOnly}
									ELSIF oflags = Unix.rdonly THEN
										f.flags := {Files.ReadOnly}
									END;
									f.key := NoKey;  f.fs := SELF;
									IncOpenFiles();
									collection.AddOld(f);
									EXIT
								END
							ELSE
								(* file exists but open failed *)  f := NIL;  EXIT
							END
						ELSIF nextdir # "" THEN
							MakePath( nextdir, name, path );  ScanPath( pos, nextdir );
						ELSE
							f := NIL;  EXIT
						END;
					END; (* loop *)
					ASSERT( (f = NIL) OR (f.fd >= 0) );
					RETURN f
				END Old0;

				(** Return the unique non-zero key of the named file, if it exists. *)
				PROCEDURE FileKey*( name: ARRAY OF CHAR ): LONGINT;
				(* 	Can not be used for Unix files as LONGINT is too small.
					In the Unix filesystem a file is identified by
					- dev	(64 bit (Linux), 32 bit (Solaris, Darwin))	+
					- ino	(32 bit)
				*)
				BEGIN
					RETURN 0
				END FileKey;

				PROCEDURE Delete0*( name: ARRAY OF CHAR;  VAR key: LONGINT; VAR res: WORD );
				VAR r: LONGINT;
				BEGIN  {EXCLUSIVE}
					r := Unix.unlink( ADDRESSOF( name ) );
					IF r = 0 THEN  res := Files.Ok
					ELSE  res := Unix.errno( )
					END;
					key := 0;
				END Delete0;


				(* return remaining old file, if any *)
				PROCEDURE TryRename*( old, new: ARRAY OF CHAR;  f: Files.File;  VAR res: WORD ): LONGINT;
				CONST Bufsize = 4096;
				VAR fdold, fdnew, fo, r: LONGINT;  n, n2: SIZE;  ostat, nstat: Unix.Status;
					buf: ARRAY Bufsize OF CHAR;
				BEGIN {EXCLUSIVE}
					fo := NoDesc;
					r:= Unix.stat( ADDRESSOF( old ), ostat );

					IF r >= 0 THEN
						r := Unix.stat( ADDRESSOF( new ), nstat );
						IF (r >= 0) & ((ostat.dev # nstat.dev) OR (ostat.ino # nstat.ino)) THEN
							 r := Unix.unlink( ADDRESSOF( new ) )  (* work around stale nfs handles *);
						END;
						r := Unix.rename( ADDRESSOF( old ), ADDRESSOF( new ) );
						IF r < 0 THEN (* could not rename, try copy *)
							res := Unix.errno( );
							IF (res = Unix.EXDEV) OR (res = Unix.ETXTBSY) THEN  (* cross device link, move the file / file busy frequently happens in VirtualBox *)
								fdold := UnixOpen( ADDRESSOF( old ), Unix.rdonly, 0 );
								fo := fdold;
								IF fdold < 0 THEN
									res := Unix.errno( );
									RETURN NoDesc;
								END;
								fdnew := UnixOpen( ADDRESSOF( new ), Unix.rdwr + Unix.creat + Unix.trunc, Unix.rwrwr );
								IF fdnew < 0 THEN
									res := Unix.errno( );
									RETURN NoDesc;
								END;
								REPEAT
									n := UnixRead( fdold, ADDRESSOF( buf ), Bufsize );
									IF n > 0 THEN
										n2 := UnixWrite( fdnew, ADDRESSOF( buf ), n );
										IF n2 < 0 THEN
											r := Unix.close( fdold );
											r := Unix.close( fdnew );
											RETURN NoDesc;
										END;
									END
								UNTIL n = 0;
								r := Unix.unlink( ADDRESSOF( old ) );
								r := Unix.close( fdold );
								r := Unix.close( fdnew );
								res := Files.Ok
							ELSE
								RETURN NoDesc (* res is Unix.rename return code *)
							END
						END;
						res := Files.Ok
					ELSE
						res := Unix.errno();
					END;
					RETURN fo;
				END TryRename;

				PROCEDURE Rename0*( old, new: ARRAY OF CHAR;  f: Files.File;  VAR res: WORD );
				VAR of: LONGINT;
				BEGIN
					of := TryRename(old, new, f, res);
				END Rename0;


				PROCEDURE CreateDirectory0*( path: ARRAY OF CHAR;  VAR res: WORD );
				VAR r: LONGINT;
				BEGIN {EXCLUSIVE}
					r := Unix.mkdir( ADDRESSOF( path ), Unix.rwxrwxrwx );
					IF r = 0 THEN  res := Files.Ok
					ELSE res := Unix.errno( )
					END
				END CreateDirectory0;


				PROCEDURE RemoveDirectory0*( path: ARRAY OF CHAR;  force: BOOLEAN;  VAR key: LONGINT; VAR res: WORD );
				VAR r: LONGINT;
				BEGIN {EXCLUSIVE}
					r := Unix.rmdir( ADDRESSOF( path ) );
					IF r = 0 THEN  res := Files.Ok
					ELSE  res := Unix.errno( )
					END
				END RemoveDirectory0;


				PROCEDURE Enumerate0*( mask: ARRAY OF CHAR;  flags: SET;  enum: Files.Enumerator );
				VAR
					path, filemask: Filename;
					isPath: BOOLEAN;
					i, j: INTEGER;  dirName, fileName, fullName, xName: Filename;
					checkSet: NameSet;  ent: Unix.Dirent;

					PROCEDURE GetEntryName;
					VAR i: INTEGER;  adr: ADDRESS;
					BEGIN
						i := -1;  adr := ADDRESSOF( ent.name );
						REPEAT  INC( i );  S.GET( adr, fileName[i] );  INC( adr )  UNTIL fileName[i] = 0X
					END GetEntryName;

					PROCEDURE EnumDir( CONST dirName: ARRAY OF CHAR );
					VAR
						dir: ADDRESS;
						tm: Unix.TmPtr;  date, time: LONGINT;
						stat: Unix.Status; r: LONGINT; p: ADDRESS;
					BEGIN
						dir := Unix.opendir( ADDRESSOF( dirName ) );
						IF dir # 0 THEN
							ent := Unix.readdir( dir );
							WHILE ent # NIL DO
								COPY( dirName, fullName );

								GetEntryName;  AppendName( fullName, fileName );
								IF (fileName[0] # '.')  & Match( fileName, filemask, 0, 0 ) THEN
									IF checkSet.Add( fileName ) THEN  (* not a covered name *)
										r := Unix.stat( ADDRESSOF( fullName ), stat );
										tm := Unix.localtime( stat.mtime );
										date := tm.year*200H + (tm.mon + 1)*20H + tm.mday;
										time := tm.hour*1000H + tm.min*40H + tm.sec;
										flags := {};
										IF IsDirectory( stat ) THEN
											flags := {Files.ReadOnly, Files.Directory}
										ELSE
											r := Unix.access( ADDRESSOF( fullName ), Unix.W_OK );
											IF r < 0 THEN  flags := {Files.ReadOnly}  END
										END;
										p := Unix.realpath(ADDRESSOF(fullName), ADDRESSOF(xName));
										IF (p # 0) THEN COPY(xName, fullName) END;
										enum.PutEntry( fullName, flags, time, date, LONGINT (stat.size) );
									END
								END;
								ent := Unix.readdir( dir );
							END;
							Unix.closedir( dir )
						END;
					END EnumDir;


				BEGIN {EXCLUSIVE}
					Files.SplitName( mask, prefix, fullName );
					Files.SplitPath( fullName, path, filemask );
					NEW( checkSet, "M###N" );
					isPath:= path#"";

					IF isPath THEN
						CleanPath(path); (*get rid of xxx/../xxx and  xxx/./xxx in the path string*)
					END;
					IF isPath & (path[0] = '/') THEN (*check for absolute path*)
						EnumDir( path);
					ELSE (*no path or relative path*)
						i := 0;  j := 0;
						LOOP (*go through the search paths, every time a complete search path has been traversed, look for the element there*)
							IF (searchPath[i] = Separator) OR (searchPath[i] = 0X) THEN
								dirName[j] := 0X;
								IF isPath THEN (*if relative path: add relative path to the current search path*)
									Files.JoinPath(dirName, path, dirName);
								END;
								EnumDir( dirName );
								IF searchPath[i] = 0X THEN  EXIT
								ELSE  INC( i );  j := 0
								END
							ELSE
								dirName[j] := searchPath[i];  INC( j );  INC( i )
							END
						END
					END;
					checkSet := NIL;
				END Enumerate0;

				PROCEDURE Has(CONST name: ARRAY OF CHAR; VAR fullName: ARRAY OF CHAR; VAR flags: SET): BOOLEAN;
				VAR r: LONGINT; p: ADDRESS; stat: Unix.Status;
				BEGIN
					r := Unix.stat( ADDRESSOF( name ), stat );
					IF r  # 0 THEN RETURN FALSE END;
					flags := {};
					IF IsDirectory( stat ) THEN
						flags := {Files.ReadOnly, Files.Directory}
					ELSE
						r := Unix.access( ADDRESSOF( name ), Unix.W_OK );
						IF r < 0 THEN  flags := {Files.ReadOnly}  END
					END;
					p := Unix.realpath(ADDRESSOF(name), ADDRESSOF(fullName));
					IF (p = 0) THEN COPY(name, fullName) END; (* no success *)
					RETURN TRUE;
				END Has;

	END UnixFileSystem;


	Buffer =	POINTER TO RECORD (Files.Hint)
					chg: BOOLEAN;
					org, size: SIZE;
					data: ARRAY Bufsize OF CHAR;
				END;

	File* = OBJECT (Files.File)
			VAR
				fd: LONGINT;
				workName, registerName: Filename;
				tempFile: BOOLEAN;
				dev: Unix.dev_t;
				ino: Unix.ino_t;
				mtime: HUGEINT;
				fsize, fpos: SIZE;
				bufs: ARRAY NBufs OF Buffer;
				swapper, state: LONGINT;


				PROCEDURE & Init( fs: Files.FileSystem );
				BEGIN
					SELF.fs := fs;  flags := {};
				END Init;

				PROCEDURE CreateUnixFile;
				VAR
					stat: Unix.Status;  r: LONGINT;
				BEGIN
					IF state = Create THEN
						GetTempName( registerName, workName )
					ELSIF state = Closed THEN
						IF registerName # "" THEN
							(* shortcut renaming in Register0 *)
							workName := registerName;  registerName := ""
						ELSE
							(* file has been finally closed *)  RETURN
						END
					END;
					r := Unix.unlink( ADDRESSOF( workName ) );
					(*unlink first to avoid stale NFS handles and to avoid reuse of inodes*)

					fd := UnixOpen( ADDRESSOF( workName ), CreateFlags, Unix.rwrwr );
					IF fd >= 0 THEN
						r := Unix.fstat( fd, stat );
						dev := stat.dev;  ino := stat.ino;  mtime := stat.mtime.sec;
						state := Open;  fpos := 0;
						IncOpenFiles( );
						collection.AddNew( SELF );
					ELSE
						Halt( SELF, TRUE, "UnixFiles.File.CreateUnixFile: open failed" );
					END
				END CreateUnixFile;


				PROCEDURE Flush( buf: Buffer );
				VAR n: SIZE;  res: WORD;  stat: Unix.Status;
				BEGIN
					IF buf.chg THEN
						IF fd = NoDesc THEN  CreateUnixFile  END;
						IF buf.org # fpos THEN
							IF Unix.lseek( fd, buf.org, 0 ) = -1 THEN
								Halt( SELF, TRUE, "UnixFiles.File.Flush: lseek failed" )
							END
						END;
						n := UnixWrite( fd, ADDRESSOF( buf.data ), buf.size );
						IF n < 0 THEN  Halt( SELF, TRUE, "UnixFiles.File.Flush: write failed" )  END;
						fpos := buf.org + buf.size;  buf.chg := FALSE;
						res := Unix.fstat( fd, stat );  mtime := stat.mtime.sec
					END
				END Flush;


				PROCEDURE Set*( VAR r: Files.Rider;  pos: LONGINT );
				BEGIN {EXCLUSIVE}
					SetX( r, pos )
				END Set;

				PROCEDURE SetX( VAR r: Files.Rider;  p: LONGINT );
				VAR  org, offset, i: LONGINT;  n: SIZE;  buf: Buffer;
				BEGIN
					r.file := SELF;  r.fs := fs;
					IF p > fsize THEN  p := LONGINT(fsize)
					ELSIF p < 0 THEN  p := 0
					END;
					offset := p MOD Bufsize;  org := p - offset;
					i := 0;
					WHILE (i < NBufs) & (bufs[i] # NIL) & (org # bufs[i].org) DO  INC( i )  END;
					IF i < NBufs THEN
						IF bufs[i] = NIL THEN
							NEW( buf );  buf.chg := FALSE;  buf.org := -1;
							bufs[i] := buf
						ELSE
							swapper := i;
							buf := bufs[swapper];  Flush( buf )
						END
					ELSE
						swapper := (swapper + 1) MOD NBufs;
						buf := bufs[swapper];  Flush( buf )
					END;
					IF buf.org # org THEN
						IF org = fsize THEN
							buf.size := 0
						ELSE
							IF fd = NoDesc THEN  CreateUnixFile  END;
							IF fpos # org THEN
								IF Unix.lseek( fd, org, 0 ) = -1 THEN
									Halt( SELF, TRUE, "UnixFiles.File.Set: lseek failed" )
								END
							END;
							n := UnixRead( fd, ADDRESSOF( buf.data ), Bufsize );
							IF n < 0 THEN
								IF p < fsize THEN  Halt( SELF, TRUE, "UnixFiles.File.Set: read failed" )
								ELSE n := 0
								END
							END;
							fpos := org + n;  buf.size := n
						END;
						buf.org := org;  buf.chg := FALSE
					ELSE
						org := LONGINT(buf.org)
					END;

					r.hint := buf;  r.apos := org;  r.bpos := offset;
					r.res := 0;  r.eof := FALSE;
				END SetX;


				PROCEDURE Pos*( VAR r: Files.Rider ): LONGINT;
				BEGIN
					RETURN r.apos + r.bpos
				END Pos;


				PROCEDURE Read*( VAR r: Files.Rider;  VAR x: CHAR );
				VAR offset: LONGINT;  buf: Buffer;
				BEGIN  {EXCLUSIVE}
					buf := r.hint(Buffer);  offset := r.bpos;
					IF r.apos # buf.org THEN
						SetX( r, r.apos + offset );
						buf := r.hint(Buffer);  offset := r.bpos
					END;
					IF (offset < buf.size) THEN
						x := buf.data[offset];  r.bpos := offset + 1
					ELSIF r.apos + offset < fsize THEN
						SetX( r, r.apos + offset );
						x := r.hint(Buffer).data[0];  r.bpos := 1
					ELSE
						x := 0X;  r.eof := TRUE
					END
				END Read;

				PROCEDURE ReadBytes*( VAR r: Files.Rider;  VAR x: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR xpos, offset, restInBuf: SIZE;  min: LONGINT;  buf: Buffer;
				BEGIN  {EXCLUSIVE}
					x[ofs] := 0X;  xpos := ofs;
					buf := r.hint(Buffer);  offset := r.bpos;
					WHILE len > 0 DO
						IF (r.apos # buf.org) OR (offset >= Bufsize) THEN
							SetX( r, r.apos + LONGINT(offset) );
							buf := r.hint(Buffer);  offset := r.bpos
						END;
						restInBuf := buf.size - offset;
						IF restInBuf = 0 THEN  r.res := len;  r.eof := TRUE;  RETURN
						ELSIF len > restInBuf THEN  min := LONGINT(restInBuf)
						ELSE  min := len
						END;
						S.MOVE( ADDRESSOF( buf.data ) + offset, ADDRESSOF( x ) + xpos, min );
						INC( offset, min );  r.bpos := LONGINT(offset);
						INC( xpos, min );  DEC( len, min )
					END;
					r.res := 0;  r.eof := FALSE;
				END ReadBytes;


				PROCEDURE Write*( VAR r: Files.Rider;  x: CHAR );
				VAR buf: Buffer;  offset: LONGINT;
				BEGIN  {EXCLUSIVE}
					buf := r.hint(Buffer);  offset := r.bpos;
					IF (r.apos # buf.org) OR (offset >= Bufsize) THEN
						SetX( r, r.apos + offset );
						buf := r.hint(Buffer);  offset := r.bpos
					END;
					buf.data[offset] := x;  buf.chg := TRUE;
					IF offset = buf.size THEN  INC( buf.size );  INC( fsize )  END;
					r.bpos := offset + 1;  r.res := Files.Ok
				END Write;

				PROCEDURE WriteBytes*( VAR r: Files.Rider;  CONST x: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR xpos, min, restInBuf, offset: LONGINT;  buf: Buffer;
				BEGIN  {EXCLUSIVE}
					xpos := ofs;  buf := r.hint(Buffer);  offset := r.bpos;
					WHILE len > 0 DO
						IF (r.apos # buf.org) OR (offset >= Bufsize) THEN
							SetX( r, r.apos + offset );
							buf := r.hint(Buffer);  offset := r.bpos
						END;
						restInBuf := Bufsize - offset;
						IF len > restInBuf THEN  min := restInBuf  ELSE  min := len  END;
						S.MOVE( ADDRESSOF( x ) + xpos, ADDRESSOF( buf.data ) + offset, min );
						INC( offset, min );  r.bpos := offset;
						IF offset > buf.size THEN
							INC( fsize, offset - buf.size );  buf.size := offset
						END;
						INC( xpos, min );  DEC( len, min );  buf.chg := TRUE
					END;
					r.res := Files.Ok
				END WriteBytes;


				PROCEDURE Length*( ): LONGINT;
				BEGIN
					RETURN LONGINT(fsize)
				END Length;


				PROCEDURE GetDate*( VAR t, d: LONGINT );
				VAR stat: Unix.Status;   r: LONGINT;  time: Unix.TmPtr;
				BEGIN {EXCLUSIVE}
					IF fd = NoDesc THEN  CreateUnixFile  END;
					r := Unix.fstat( fd, stat );
					time := Unix.localtime( stat.mtime );
					t := time.sec + ASH( time.min, 6 ) + ASH( time.hour, 12 );
					d := time.mday + ASH( time.mon + 1, 5 ) + ASH( time.year, 9 );
				END GetDate;


				PROCEDURE SetDate*( t, d: LONGINT );
				TYPE
					Time = RECORD actime, modtime: LONGINT END;
				VAR
					tm: Unix.Tm;  buf: Time;  r: LONGINT;  path: Filename;
				BEGIN {EXCLUSIVE}
					IF registerName # "" THEN  COPY( registerName, path )
					ELSE  COPY( workName, path )
					END;
					(* get year and timezone *)
					(* fill in new date *)
					tm.isdst := -1;  tm.sec := t MOD 64;  tm.min := t DIV 64 MOD 64;
					tm.hour := t DIV 4096 MOD 32;
					tm.mday := d MOD 32;  tm.mon := d DIV 32 MOD 16 - 1;  tm.year := d DIV 512;
					tm.wday := 0;  tm.yday := 0;
					buf.actime := Unix.mktime( tm );  buf.modtime := buf.actime;
					r := Unix.utime( ADDRESSOF( path ), ADDRESSOF( buf ) );
				END SetDate;


				PROCEDURE GetAttributes*( ): SET;
				BEGIN {EXCLUSIVE}
					RETURN flags
				END GetAttributes;

				PROCEDURE SetAttributes*( attr: SET );
				BEGIN {EXCLUSIVE}
					(* flags := attr	*)
				END SetAttributes;


				PROCEDURE Register0*( VAR res: WORD );
				VAR fo, r: LONGINT;
				BEGIN {EXCLUSIVE}
					IF (state = Create) & (registerName # "") THEN
						state := Closed (* shortcut renaming *)   ;
					END;

					FlushBuffers;

					IF registerName # "" THEN
						fo := unixFS.TryRename( workName, registerName, SELF, res );
						IF res # Files.Ok THEN
							Halt( SELF, FALSE, "UnixFiles.File.Register: rename failed" )
						END;

						IF fo # NoDesc THEN (* SELF still refers to old file *)
							r := Unix.close( fd );  (* VirtualBox ! Can only delete file when closed. *)
							r := Unix.unlink( ADDRESSOF( workName ) );
							fd := UnixOpen( ADDRESSOF( registerName ), Unix.rdwr, Unix.rwrwr );
						END;

						workName := registerName;  registerName := ""
					END;
				END Register0;


				PROCEDURE Update*;
				BEGIN {EXCLUSIVE}
					FlushBuffers
				END Update;


				PROCEDURE FlushBuffers;
				VAR i: LONGINT;
				BEGIN
					IF fd = NoDesc THEN  CreateUnixFile  END;
					FOR i := 0 TO NBufs - 1 DO
						IF bufs[i] # NIL THEN  Flush( bufs[i] )  END
					END;
				END FlushBuffers;


				PROCEDURE Finalize*;
				VAR r: LONGINT;
				BEGIN {EXCLUSIVE}
					IF tempFile THEN
						IF fd # NoDesc THEN
							r := Unix.close( fd );
							fd := NoDesc
						END;
						r := Unix.unlink( ADDRESSOF( workName ) );
					ELSE
						FlushBuffers;
						IF fd # NoDesc THEN
							r := Unix.close( fd );
							fd := NoDesc;
						END;
					END;
					state := Closed;
					DecOpenFiles()
				END Finalize;

				PROCEDURE Close;
				BEGIN
					Finalize;
					collection.newFiles.Remove( SELF );
					collection.oldFiles.Remove( SELF );
				END Close;

				PROCEDURE GetName*( VAR name: ARRAY OF CHAR );
				BEGIN {EXCLUSIVE}
					IF registerName = "" THEN  COPY( workName, name ) ;
					ELSE  COPY( registerName, name )
					END;
					CleanPath( name )
				END GetName;

			END File;

	PROCEDURE EnumFinalize( f: ANY;  VAR cont: BOOLEAN );
	VAR F: File;
	BEGIN
		F := f( File );  F.Finalize();  cont := TRUE;
	END EnumFinalize;

(*===================================================================*)

	(** Get the current directory. *)
	PROCEDURE GetWorkingDirectory*( VAR path: ARRAY OF CHAR );
	BEGIN
		COPY( cwd, path )
	END GetWorkingDirectory;

	(** Change to directory path. *)
	PROCEDURE ChangeDirectory*( CONST path: ARRAY OF CHAR;  VAR done: BOOLEAN );
	VAR r: LONGINT;  newdir: Filename;
	BEGIN
		IF path[0] # '/' THEN
			COPY( cwd, newdir );  AppendName( newdir, path );
			CleanPath( newdir )
		ELSE
			COPY( path, newdir );
		END;
		r := Unix.chdir( ADDRESSOF( newdir ) );
		IF r = 0 THEN  COPY( newdir, cwd );  done := TRUE   ELSE  done := FALSE   END
	END ChangeDirectory;

(*===================================================================*)

	PROCEDURE StripPath*( CONST path: ARRAY OF CHAR;  VAR name: ARRAY OF CHAR );
	VAR i, p: INTEGER;  c: CHAR;
	BEGIN
		i := 0;  p := 0;
		REPEAT
			IF path[i] = '/' THEN  p := i + 1  END;
			INC( i )
		UNTIL path[i] = 0X;
		i := 0;
		REPEAT  c := path[p];  name[i] := c;  INC( i );  INC( p )  UNTIL c = 0X
	END StripPath;


	PROCEDURE CleanPath*( VAR path: ARRAY OF CHAR );
	(*
		/aaa/../bbb/./ccc/../ddd/.  ==>   /bbb/ddd
		../aaa  ==>  CWD/../aaa  ==>  . . .
	*)
	VAR
		i, prevNameStart, nameStart: INTEGER;
		c1, c2, c3: CHAR;

		PROCEDURE prependCWD;
		VAR tmp: ARRAY 256 OF CHAR;
		BEGIN
			COPY( cwd, tmp ); AppendName( tmp, path );  COPY( tmp, path )
		END prependCWD;

		PROCEDURE restart;
		BEGIN
			IF path[0] = '/' THEN  nameStart := 1  ELSE  nameStart := 0  END;
			i := -1;  prevNameStart := -1;
		END restart;

		PROCEDURE shift( p0, p1: INTEGER );
		VAR c: CHAR;
		BEGIN
			REPEAT  c := path[p1];  path[p0] := c;  INC( p0 );  INC( p1 )  UNTIL c = 0X;
			IF p0 > 1 THEN  restart  ELSE  i := 0  END
		END shift;

	BEGIN
		restart;
		REPEAT
			INC( i );
			IF i = nameStart THEN
				c1 := path[i];  c2 := path[i + 1];  c3 := path[i + 2];
				IF c1 = '/' THEN  shift( i, i + 1 ) (* // *)
				ELSIF c1 = '.' THEN
					IF c2 = 0X THEN
						IF i > 1 THEN  DEC( i )  END;
						path[i] := 0X
					ELSIF c2 = '/' THEN  shift( i, i + 2 );   (* ./ *)
					ELSIF (c2 = '.') & ((c3 = 0X) OR (c3 = '/')) THEN  (* .. *)
						IF i = 0 THEN  prependCWD;  restart
						ELSIF c3 = 0X THEN DEC( i ); path[i] := 0X
						ELSIF c3 = '/' THEN  (* ../ *)
							IF prevNameStart >= 0 THEN  shift( prevNameStart, i + 3 )  END
						END
					END
				END
			ELSIF path[i] = '/' THEN
				IF i > 0 THEN  prevNameStart := nameStart  END;
				nameStart := i + 1
			END;
		UNTIL (i >= 0) & (path[i] = 0X);
		IF (i > 1) & (path[i - 1] = '/') THEN  path[i - 1] := 0X  END;
		IF path = "" THEN  COPY( cwd, path )  END;
	END CleanPath;


	PROCEDURE Match( CONST name, pat: ARRAY OF CHAR;  i, j: INTEGER ): BOOLEAN;
	BEGIN
		IF (name[i] = 0X) & (pat[j] = 0X) THEN  RETURN TRUE
		ELSIF pat[j] # "*" THEN  RETURN (name[i] = pat[j]) & Match( name, pat, i + 1, j + 1 )
		ELSE  (* pat[j] = "*", name[i] may be 0X *)
			RETURN Match( name, pat, i, j + 1 ) OR ((name[i] # 0X) & Match( name, pat, i + 1, j ))
		END
	END Match;


	PROCEDURE Append( VAR a: Filename;  CONST this: ARRAY OF CHAR );
	VAR i, j: LONGINT;
	BEGIN
		i := 0;  j := 0;
		WHILE a[i] # 0X DO  INC( i )  END;
		WHILE (i < LEN( a ) - 1) & (this[j] # 0X) DO  a[i] := this[j];  INC( i );  INC( j )  END;
		a[i] := 0X
	END Append;

	PROCEDURE AppendName( VAR path: Filename;  CONST filename: ARRAY OF CHAR );
	VAR i, j, max: LONGINT;
	BEGIN
		i := 0;  j := 0;  max := LEN( path ) - 1;
		WHILE path[i] # 0X DO  INC( i )  END;
		IF (i > 0) & (path[i - 1] # "/") THEN  path[i] := "/";  INC( i );  path[i] := 0X  END;
		Append( path, filename );
	END AppendName;


	PROCEDURE AppendInt( VAR str: Filename; n: LONGINT );
	VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO  INC(i)  END;
		WHILE n > 0 DO  str[i] := CHR( n MOD 10 + ORD('0') );  n := n DIV 10;  INC(i)  END;
		str[i] := 0X
	END AppendInt;


	PROCEDURE IsFullName( CONST name: ARRAY OF CHAR ): BOOLEAN;
	VAR i: INTEGER;  ch: CHAR;
	BEGIN
		i := 0;  ch := name[0];
		WHILE (ch # 0X) & (ch # "/") DO  INC( i );  ch := name[i]  END;
		RETURN ch = "/"
	END IsFullName;

	PROCEDURE Halt( f: File;  unixError: BOOLEAN;  CONST msg: ARRAY OF CHAR );
	VAR fd, errno, state: LONGINT;
		workName, registerName: Filename;
	BEGIN
		IF f = NIL THEN
			workName := "???";  registerName := "???"
		ELSE
			workName := f.workName;  registerName := f.registerName;
			fd := f.fd; state := f.state
		END;
		IF unixError THEN  errno := Unix.errno( );  Unix.Perror( msg )  END;
		HALT( 99 )
	END Halt;


	PROCEDURE ResetBuffers( f: File;  VAR stat: Unix.Status );
	VAR i: INTEGER;
	BEGIN
		f.fsize := stat.size;
		IF (f.mtime # stat.mtime.sec) THEN
			FOR i := 0 TO NBufs - 1 DO
				IF f.bufs[i] # NIL THEN  f.bufs[i].org := -1;  f.bufs[i] := NIL  END;
			END;
			f.swapper := -1;  f.mtime := stat.mtime.sec
		END
	END ResetBuffers;


	PROCEDURE MakePath( CONST dir, name: ARRAY OF CHAR;  VAR dest: ARRAY OF CHAR );
	VAR i, j: INTEGER;
	BEGIN
		i := 0;  j := 0;
		WHILE dir[i] # 0X DO  dest[i] := dir[i];  INC( i )  END;
		IF (i>0) & (dest[i - 1] # "/") THEN  dest[i] := "/";  INC( i )  END;
		WHILE name[j] # 0X DO  dest[i] := name[j];  INC( i );  INC( j )  END;
		dest[i] := 0X
	END MakePath;


	PROCEDURE ScanPath( VAR pos: LONGINT;  VAR dir: ARRAY OF CHAR );
	VAR i: LONGINT;  ch: CHAR;
	BEGIN
		i := 0;  ch := searchPath[pos];
		WHILE ch = Separator DO  INC( pos );  ch := searchPath[pos]  END;
		WHILE (ch >= " ") & (ch # Separator) DO  dir[i] := ch;  INC( i );  INC( pos );  ch := searchPath[pos]  END;
		dir[i] := 0X
	END ScanPath;


	PROCEDURE GetTempName( CONST finalName: ARRAY OF CHAR;  VAR tempName: Filename );
	VAR n, i, j, pe, pid: LONGINT;
	BEGIN
		INC(tempno);  n := tempno;  i := 0;  j := 0; pe := 1;
		WHILE finalName[j] = ' ' DO  INC(j)  END;   (* skip leading spaces *)
		IF finalName[j] # "/" THEN  (* relative pathname *)
			WHILE cwd[i] # 0X DO  tempName[i] := cwd[i];  INC(i)  END;
			IF tempName[i - 1] # '/' THEN  tempName[i] := '/';  INC(i)  END;
			pe := i - 1
		END;
		WHILE finalName[j] # 0X DO  tempName[i] := finalName[j];  INC(i);  INC(j)  END;
		WHILE (i > pe) & (tempName[i-1] # '/') DO  DEC(i)  END;  (* remove filename *)
		tempName[i] := 0X;
		Append( tempName, ".tmp." );
		AppendInt( tempName, n );  Append( tempName, "." );
		pid := Unix.getpid();
		AppendInt( tempName, pid )
	END GetTempName;

	PROCEDURE Install;
	VAR aliasFS: AliasFileSystem;
	BEGIN
		NEW(collection);
		NEW( unixFS );  (*  Files.Add( unixFS, "" );	*)
		NEW( aliasFS, unixFS );  Files.Add( aliasFS, "searcher" )
	END Install;



	PROCEDURE Initialize;
	VAR a: ADDRESS;  i: INTEGER;  ch: CHAR;
	BEGIN
		(* get current working directory *)
		a := Unix.getenv( ADDRESSOF( "PWD" ) );
		IF a > 0 THEN
			i := 0;
			REPEAT  S.GET( a, ch );  INC( a );  cwd[i] := ch;  INC( i )  UNTIL ch = 0X;
		ELSE
			(* $PWD not set *)
			a := Unix.getcwd( ADDRESSOF( cwd ), LEN( cwd ) )
		END;
		i := 0;
		WHILE cwd[i] # 0X DO  INC( i )  END;
		DEC( i );
		IF (i > 0) & (cwd[i] = '/') THEN  cwd[i] := 0X  END;

		(* get search pathes *)
		a := Unix.getenv( ADDRESSOF( "AOSPATH" ) );  i := 0;
		IF a = 0 THEN
		(*	Log.String( "UnixFiles.Initialize: environment variable AOSPATH not defined" );  Log.Ln; *)
		ELSE
			REPEAT
				S.GET( a, ch );  INC( a );
				IF ch = ":" THEN  ch := Separator  END;
				searchPath[i] := ch;  INC( i )
			UNTIL ch = 0X;
		END;
		tempno := 1;  openfiles := 0;
		Modules.InstallTermHandler( Finalization )
	END Initialize;


	(*!	The system calls open, read and write return -1 when they get interrupted
		by receiving a signal. Possibly through Objects.SuspendActivities() (GC).
	*)
	PROCEDURE UnixOpen( path: ADDRESS; flags: SET32; permissions: Unix.mode_t ): LONGINT;
	VAR
		fd, fo, errno: LONGINT;  failure: BOOLEAN;
	BEGIN
		failure := FALSE;
		REPEAT
			fd := Unix.open( path, flags, permissions );
			IF fd < 0 THEN
				errno := Unix.errno();
				IF errno IN  {Unix.ENFILE, Unix.EMFILE} THEN
					fo := openfiles;  Kernel.GC;  WaitClose( fo )
				ELSIF (errno = Unix.EINVAL) & (openfiles > 1000) THEN
					(* in Solaris open fails with EINVAL ??? *)
					fo := openfiles;  Kernel.GC;  WaitClose( fo )
				ELSIF errno # Unix.EINTR THEN
					failure := TRUE
				END
			END
		UNTIL (fd >= 0) OR failure;
		RETURN fd
	END UnixOpen;

	PROCEDURE UnixRead( fd: LONGINT; buf: ADDRESS; len: SIZE ): SIZE;
	VAR n: SIZE;
	BEGIN
		REPEAT
			n := Unix.read( fd, buf, len )
		UNTIL (n >= 0) OR (Unix.errno() # Unix.EINTR);
		RETURN n
	END UnixRead;

	PROCEDURE UnixWrite( fd: LONGINT; buf: ADDRESS; len: SIZE ): SIZE;
	VAR n: SIZE;
	BEGIN
		REPEAT
			n := Unix.write( fd, buf, len )
		UNTIL (n >= 0) OR (Unix.errno() # Unix.EINTR);
		RETURN n
	END UnixWrite;


	PROCEDURE AddSearchPath*( context: Commands.Context );
	VAR name: Files.FileName;  i, j: LONGINT;  ch : CHAR;
	BEGIN
		IF context.arg.GetString( name ) THEN
			CleanPath( name );
			i := 0;  j := 0;
			WHILE searchPath[i] # 0X DO  INC( i )  END;
			searchPath[i] := Separator;  INC( i );
			REPEAT
				ch := name[j];  searchPath[i] := ch;
				INC( j );  INC( i );
			UNTIL ch = 0X;
		END;
	END AddSearchPath;

	PROCEDURE SetWorkPath*( context: Commands.Context );
	VAR name: Files.FileName; done: BOOLEAN;
	BEGIN
		IF context.arg.GetString( name ) THEN
			ChangeDirectory( name, done );
			IF ~done THEN
				context.error.String( "could not change directory to " );  context.error.String( name );  context.error.Ln
			END
		END
	END SetWorkPath;

	PROCEDURE Finalization;
	VAR ft: Files.FileSystemTable;  i: LONGINT;
	BEGIN
		Files.GetList( ft );
		IF ft # NIL THEN
			FOR i := 0 TO LEN( ft^ ) - 1 DO
				IF ft[i] IS AliasFileSystem THEN  Files.Remove( ft[i] )  END
			END
		END;
		collection.Finalize;
		unixFS.Finalize;
	END Finalization;

	PROCEDURE DecOpenFiles;
	BEGIN{EXCLUSIVE}
		DEC(openfiles);
	END DecOpenFiles;

	PROCEDURE IncOpenFiles;
	BEGIN{EXCLUSIVE}
		INC(openfiles);
	END IncOpenFiles;


	PROCEDURE WaitClose(no: LONGINT);
	BEGIN{EXCLUSIVE}
		AWAIT(openfiles < no);
	END WaitClose;


BEGIN
	Initialize;
	Install
END UnixFiles.
