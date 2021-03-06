MODULE UsbBuffers; (** AUTHOR ""; PURPOSE ""; *)

CONST
	Align = 32;

TYPE
	BufferPtr * = Buffer;
	Buffer * = OBJECT
	VAR
		data: POINTER TO ARRAY OF CHAR;
		ofs: LONGINT;

		PROCEDURE & SetSize * (size: LONGINT);
		BEGIN
			NEW(data, size + Align);
			ofs := Align - ADDRESSOF(data[0]) MOD Align;
			ASSERT(ADDRESSOF(data[ofs]) MOD Align = 0)
		END SetSize;

		PROCEDURE ToArray * (): POINTER TO ARRAY OF CHAR;
		VAR
			ptr: POINTER TO ARRAY OF CHAR;
			i: LONGINT;
		BEGIN
			NEW(ptr, LEN(data) - Align);
			FOR i := 0 TO LEN(ptr) - 1 DO ptr[i] := data[ofs + i] END;
			RETURN ptr
		END ToArray;

		PROCEDURE ToArrayOfs * (): LONGINT;
		BEGIN
			RETURN ofs
		END ToArrayOfs;

		OPERATOR "[]" * (idx: LONGINT): CHAR;
		BEGIN
			ASSERT(idx >= 0, 7);
			ASSERT(idx < LEN(data) - Align, 7);
			RETURN data[ofs + idx]
		END "[]";

		OPERATOR "[]" * (idx: LONGINT; val: CHAR);
		BEGIN
			ASSERT(idx >= 0, 7);
			ASSERT(idx < LEN(data) - Align, 7);
			data[ofs + idx] := val
		END "[]";
	END Buffer;

	PROCEDURE GetDataAddress * (buffer: Buffer): ADDRESS;
	BEGIN
		ASSERT(ADDRESSOF(buffer.data[buffer.ofs]) # 0);
		RETURN ADDRESSOF(buffer.data[buffer.ofs])
	END GetDataAddress;

	OPERATOR "LEN" * (buffer: Buffer): LONGINT;
	BEGIN
		RETURN LEN(buffer.data) - Align
	END "LEN";
END UsbBuffers.
