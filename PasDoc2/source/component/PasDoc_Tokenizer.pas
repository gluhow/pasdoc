{
  @author(Johannes Berg <johannes@sipsolutions.de>)
  @author(Ralf Junker (delphi@zeitungsjunge.de))
  @author(Marco Schmidt (marcoschmidt@geocities.com))
  @author(Michalis Kamburelis)
  @abstract(Provides simplified Pascal tokenizer.)

The @link(TTokenizer) object creates @link(TToken) objects (tokens) for the
Pascal programming language from a character input stream.

The @link(PasDoc_Scanner) unit does the same (it actually uses this unit's
tokenizer), with the exception that it evaluates compiler directives,
which are comments that start with a dollar sign. }

unit PasDoc_Tokenizer;

{$I pasdoc_defines.inc}

interface

uses
  PasDoc_Utils,
  PasDoc_Types,
  PasDoc_Base,
  Classes;

type
  { @abstract(Converts an input TStream to a sequence of @link(TToken) objects.) }
  TTokenizer = class(TObject)
  private
    function StreamPosition: TTextStreamPos;
  protected
  {$IFDEF old}
    FOnMessage: TPasDocMessageEvent;
    FVerbosity: Cardinal;
  {$ELSE}
    FDoc: TPasDoc;
  {$ENDIF}
    { if @link(IsCharBuffered) is true, this field contains the buffered
      character }
    BufferedChar: Char;
    { true if end of stream @link(Stream) has been reached, false otherwise }
    EOS: Boolean;
    { if this is true, @link(BufferedChar) contains a buffered character;
      the next call to @link(GetChar) or @link(PeekChar) will return this
      character, not the next in the associated stream @link(Stream) }
    IsCharBuffered: Boolean;
    { current row in stream @link(Stream); useful when giving error messages }
    Row: Integer;
    { the input stream this tokenizer is working on }
    Stream: TStream;
    FStreamName: string;
    FStreamPath: string;

  {$IFDEF old}
    procedure DoMessage(const AVerbosity: Cardinal; const MessageType:
      TPasDocMessageType; const AMessage: string; const AArguments: array of const);
  {$ELSE}
    DoMessage: TPasDocMessenger;
  {$ENDIF}
    procedure DoError(const AMessage: string; const AArguments: array of
      const; const AExitCode: Word);

    procedure CheckForDirective(const t: TToken);
    procedure ConsumeChar;

    { Uses default symbol representation, from SymbolNames[st] }
    function CreateSymbolToken(st: TTokenType; const s: string = ''): TToken;

    function GetChar(out c: Char): Boolean;
    function PeekChar(out c: Char): Boolean;
    function ReadCommentType1: TToken;
    function ReadCommentType2: TToken;
    function ReadCommentType3: TToken;
    function ReadAttAssemblerRegister: TToken;
    function ReadLiteralString(var t: TToken): Boolean;
    function ReadToken(c: Char; const s: TCharSet; const TT: TTokenType; var
      t: TToken): Boolean;

  public
    { Creates a TTokenizer and associates it with given input TStream.
      Note that AStream will be freed when this object will be freed. }
  {$IFDEF old}
    constructor Create(
      const AStream: TStream;
      const OnMessageEvent: TPasDocMessageEvent;
      const VerbosityLevel: Cardinal;
      const AStreamName, AStreamPath: string);
  {$ELSE}
    constructor Create(
      ADoc: TPasDoc;
      const AStream: TStream;
      const AStreamName, AStreamPath: string);
  {$ENDIF}
    { Releases all dynamically allocated memory. }
    destructor Destroy; override;
    function HasData: Boolean;
    function GetStreamInfo: string;
    function GetToken: TToken;
    { Skips all chars until it encounters either $ELSE or $ENDIF compiler defines. }
    function SkipUntilCompilerDirective: TToken;

  {$IFDEF old}
    property OnMessage: TPasDocMessenger read FOnMessage write FOnMessage;
    property Verbosity: Cardinal read FVerbosity write FVerbosity;
  {$ELSE}
  {$ENDIF}
    property StreamName: string read FStreamName;

    { This is the path where the underlying file of this stream is located.

      It may be an absolute path or a relative path. Relative paths
      are always resolved vs pasdoc current directory.
      This way user can give relative paths in command-line
      when writing Pascal source filenames to parse.

      In particular, this may be '' to indicate current dir.

      It's always specified like it was processed by
      IncludeTrailingPathDelimiter, so it has trailing PathDelim
      included (unless it was '', in which case it remains empty). }
    property StreamPath: string read FStreamPath;
  end;

implementation

uses
  SysUtils;

const
  //Whitespace = [#9, #10, #13, ' '];
  Letters = ['A'..'Z', 'a'..'z'];
  DecimalDigits = ['0'..'9'];
  HexadecimalDigits = DecimalDigits + ['A'..'F', 'a'..'f'];
  IdentifierStart = ['_'] + Letters;
  IdentifierOther = IdentifierStart + DecimalDigits;
  CharOther = HexadecimalDigits + ['$'];
  NumberStart = DecimalDigits + ['$'];
  NumberOther = HexadecimalDigits + ['.', '+', '-'];
  QuoteChar = '''';
  NUM_SINGLE_CHAR_SYMBOLS = 10;
  SingleCharSymbols: array[0..NUM_SINGLE_CHAR_SYMBOLS - 1] of
  record
    c: Char;
    s: TTokenType;
  end =
  ((c: ';'; s: SYM_SEMICOLON),
    (c: ','; s: SYM_COMMA),
    (c: '['; s: SYM_LEFT_BRACKET),
    (c: ']'; s: SYM_RIGHT_BRACKET),
    (c: '+'; s: SYM_PLUS),
    (c: '-'; s: SYM_MINUS),
    (c: '*'; s: SYM_ASTERISK),
    (c: '='; s: SYM_EQUAL),
    (c: '^'; s: SYM_ROOF),
    (c: '@'; s: SYM_AT));


{ ---------------------------------------------------------------------------- }
{ TTokenizer }
{ ---------------------------------------------------------------------------- }

{$IFDEF old}
constructor TTokenizer.Create(
  const AStream: TStream;
  const OnMessageEvent: TPasDocMessageEvent;
  const VerbosityLevel: Cardinal;
  const AStreamName, AStreamPath: string);
{$ELSE}
constructor TTokenizer.Create(ADoc: TPasDoc; const AStream: TStream;
  const AStreamName, AStreamPath: string);
{$ENDIF}
begin
  inherited Create;
{$IFDEF old}
  FOnMessage := OnMessageEvent;
  FVerbosity := VerbosityLevel;
{$ELSE}
  FDoc := ADoc;
{$ENDIF}
  Row := 1;
  Stream := AStream;
  FStreamName := AStreamName;
  FStreamPath := AStreamPath;
end;

{ ---------------------------------------------------------------------------- }

destructor TTokenizer.Destroy;
begin
  Stream.Free;
  inherited;
end;

{ ---------------------------------------------------------------------------- }

procedure TTokenizer.CheckForDirective(const t: TToken);
begin
  if SCharIs(T.CommentContent, 1, '$') then
    t.MyType := TOK_DIRECTIVE;
end;

{ ---------------------------------------------------------------------------- }

procedure TTokenizer.ConsumeChar;
begin
  IsCharBuffered := False;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.CreateSymbolToken(st: TTokenType; const s: string = ''): TToken;
begin
  Result := TToken.Create(st);
  with Result do begin
    Data := TokenNames[st];
  end;
end;

{ ---------------------------------------------------------------------------- }

procedure TTokenizer.DoError(const AMessage: string; const AArguments: array
  of const; const AExitCode: Word);
begin
  raise EPasDoc.Create(AMessage + Format(' (at %s)', [GetStreamInfo]),
    AArguments, AExitCode);
end;

{ ---------------------------------------------------------------------------- }

{$IFDEF old}
procedure TTokenizer.DoMessage(const AVerbosity: Cardinal; const MessageType:
  TPasDocMessageType; const AMessage: string; const AArguments: array of const);
begin
  if (AVerbosity < FVerbosity) and Assigned(FOnMessage) then
    FOnMessage(MessageType, Format(AMessage, AArguments), AVerbosity);
end;
{$ELSE}
{$ENDIF}

{ ---------------------------------------------------------------------------- }

function TTokenizer.GetChar(out c: Char): Boolean;
begin
  if IsCharBuffered then begin
    c := BufferedChar;
    IsCharBuffered := False;
    Result := True;
  end
  else begin
    Result := Stream.Position < Stream.Size;
    if Result then begin
      Stream.Read(c, 1);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.GetStreamInfo: string;
begin
  GetStreamInfo := FStreamName + '(' + IntToStr(Row) + ')';
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.HasData: Boolean;
begin
  HasData := IsCharBuffered or (Stream.Position < Stream.Size);
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.StreamPosition: TTextStreamPos;
begin
  if IsCharBuffered then
    Result := Stream.Position - 1 else
    Result := Stream.Position;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.GetToken: TToken;
var
  c: Char;
  //MaybeKeyword: eKeyword;
  s: string;
  J: Integer;
  BeginPosition: integer;
begin
  Result := nil;
  BeginPosition := StreamPosition; //used in finally
  try
    if not GetChar(c) then
      DoError('Tokenizer: could not read character', [], 0);

    if c in Whitespace then begin
      if ReadToken(c, Whitespace, TOK_WHITESPACE, Result) then
          { after successful reading all whitespace characters, update
            internal row counter to be able to state current row on errors;
            TODO: will fail on Mac files (row is 13) }
        Inc(Row, StrCountCharA(Result.Data, #10))
      else
        DoError('Tokenizer: could not read character', [], 0);
    end else if c in IdentifierStart then begin
      if ReadToken(c, IdentifierOther, TOK_IDENTIFIER, Result) then begin
        s := Result.Data;
        { check if identifier is a keyword }
        Result.MyType := KeyWordByName(s);
        if (Result.MyType = KEY_INVALIDKEYWORD) then
          Result.Directive := StandardDirectiveByName(s)
        else
          Result.Directive := SD_INVALIDSTANDARDDIRECTIVE;
      end;
    end else if c in NumberStart then
      ReadToken(c, NumberOther, TOK_NUMBER, Result)
    else
      case c of
        QuoteChar:
          ReadLiteralString(Result);
        '#':
          ReadToken(c, CharOther, TOK_STRING, Result);
        '{': begin
            Result := ReadCommentType1;
            CheckForDirective(Result);
          end;
        '(': begin
            c := ' ';
            if HasData and not PeekChar(c) then
              DoError('Tokenizer: could not read character', [], 0);
            case c of
              '*': begin
                  ConsumeChar;
                  Result := ReadCommentType2;
                  CheckForDirective(Result);
                end;
              '.': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_LEFT_BRACKET, '(.');
                end;
            else
              Result := CreateSymbolToken(SYM_LEFT_PARENTHESIS);
            end;
          end;
        ')': begin
            c := ' ';
            Result := CreateSymbolToken(SYM_RIGHT_PARENTHESIS);
          end;
        '.': begin
            c := ' ';
            if HasData and (not PeekChar(c)) then Exit;
            case c of
              '.': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_RANGE);
                end;
              ')': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_RIGHT_BRACKET, '.)');
                end;
            else
              Result := CreateSymbolToken(SYM_PERIOD);
            end;
          end;
        '/': begin
            c := ' ';
            if HasData and (not PeekChar(c)) then Exit;
            case c of
              '/': begin
                  ConsumeChar;
                  Result := ReadCommentType3;
                end;
            else
              Result := CreateSymbolToken(SYM_SLASH);
            end;
          end;
        ':': begin
            c := ' ';
            if HasData and (not PeekChar(c)) then Exit;
            case c of
              '=': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_ASSIGN);
                end;
            else
              Result := CreateSymbolToken(SYM_COLON);
            end;
          end;
        '<': begin
            c := ' ';
            if HasData and (not PeekChar(c)) then Exit;
            case c of
              '=': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_LESS_THAN_EQUAL);
                end;
            else
              Result := CreateSymbolToken(SYM_LESS_THAN);
            end;
          end;
        '>': begin
            c := ' ';
            if HasData and (not PeekChar(c)) then Exit;
            case c of
              '=': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_GREATER_THAN_EQUAL);
                end;
            else
              Result := CreateSymbolToken(SYM_GREATER_THAN);
            end;
          end;
        '*': begin
            c := ' ';
            if HasData and (not PeekChar(c)) then Exit;
            case c of
              '*': begin
                  ConsumeChar;
                  Result := CreateSymbolToken(SYM_POWER);
                end;
            else
              Result := CreateSymbolToken(SYM_ASTERISK);
            end;
          end;
        '\': Result := CreateSymbolToken(SYM_BACKSLASH);
        '%': Result := ReadAttAssemblerRegister;
      else begin
          for J := 0 to NUM_SINGLE_CHAR_SYMBOLS - 1 do begin
            if (c = SingleCharSymbols[J].c) then begin
              Result := CreateSymbolToken(SingleCharSymbols[J].s, c);
              exit;
            end;
          end;
          DoError('Invalid character in Pascal input stream', [], 0);
        end;
      end;
  finally
    if Result <> nil then
    begin
      Result.StreamName := StreamName;
      Result.BeginPosition := BeginPosition;
      Result.EndPosition := StreamPosition;
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.PeekChar(out c: Char): Boolean;
begin
  if IsCharBuffered then begin
    c := BufferedChar;
    Result := True;
  end
  else begin
    if Stream.Position < Stream.Size then begin
      Stream.Read(c, 1);
      BufferedChar := c;
      IsCharBuffered := True;
      Result := True;
    end
    else begin
      EOS := True;
      PeekChar := False;
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.ReadCommentType1: TToken;
var
  c: Char;
begin
  Result := TToken.Create(TOK_COMMENT_EXT);
  with Result do 
  begin
    CommentContent := '';
    repeat
      if not HasData or not GetChar(c) then Exit;
      if c = #10 then Inc(Row);
      CommentContent := CommentContent + c; // TODO: Speed up!
    until c = '}';
    
    Data := '{' + CommentContent;
    (* Remove last '}' from CommentContent *)
    SetLength(CommentContent, Length(CommentContent) - 1);
  end;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.ReadCommentType2: TToken;
var
  c: Char;
begin
  Result := TToken.Create(TOK_COMMENT_PAS);
  Result.CommentContent := '';
  if not HasData or not GetChar(c) then Exit;
  repeat
    Result.CommentContent := Result.CommentContent + c;

    if c <> '*' then begin
      if c = #10 then Inc(Row);
      if not HasData or not GetChar(c) then Exit;
    end else begin
      if not HasData or not GetChar(c) then Exit;
      if c = ')' then
        begin
          ConsumeChar;
          Result.Data := '(*' + Result.CommentContent + ')';
          { Remove last '*' from Result.CommentContent }
          SetLength(Result.CommentContent, Length(Result.CommentContent) - 1);
          Break;
        end;
    end;
  until False;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.ReadCommentType3: TToken;
var
  c: Char;
begin
  Result := TToken.Create(TOK_COMMENT_CSTYLE);
  with Result do
  begin
    CommentContent := '';

    while HasData and GetChar(c) do
    begin
      case c of
        #10: begin Inc(Row); break end;
        #13: break;
        else CommentContent := CommentContent + c;
      end;
    end;

    Data := '//' + CommentContent;
  end;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.ReadAttAssemblerRegister: TToken;
var
  C: char;
begin
  Result := TToken.Create(TOK_ATT_ASSEMBLER_REGISTER);

  Result.Data := '%';
  repeat
    if (not HasData) or (not PeekChar(C)) then Exit;
    if C in ['a'..'z', 'A'..'Z', '0'..'9'] then
    begin
      GetChar(C);
      Result.Data := Result.Data + C;
    end else
      Break;
  until false;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.ReadLiteralString(var t: TToken): Boolean;

  procedure ReleaseToken;
  begin
    t.Free;
    t := nil;
  end;

var
  c: Char;
  Finished: Boolean;
begin
  Finished := False;

  t := TToken.Create(TOK_STRING);
  t.Data := '''';

  repeat
    if not (Stream.Position < Stream.Size) then begin
      ReleaseToken;
      DoError('Tokenizer: unexpected end of stream', [], 0);
    end;
    if not GetChar(c) then begin
      ReleaseToken;
      DoError('Tokenizer: could not read character', [], 0);
    end;
    if c = QuoteChar then begin
      if not PeekChar(c) then begin
        ReleaseToken;
        DoError('Tokenizer: could not peek character', [], 0)
      end;
      if c = QuoteChar then { escaped single quote within string } begin
        ConsumeChar;
        t.Data := t.Data + QuoteChar;
      end
      else { end of string } begin
        Finished := True;
      end;
      t.Data := t.Data + QuoteChar;
    end
    else begin
      t.Data := t.Data + c;
    end;
  until Finished;
  ReadLiteralString := True;
end;

{ ---------------------------------------------------------------------------- }

function TTokenizer.ReadToken(c: Char; const s: TCharSet; const TT:
  TTokenType; var t: TToken): Boolean;
begin
  Assert(t=nil);
  Result := False;

  t := TToken.Create(TT);
  t.Data := c;
  repeat
    if not PeekChar(c) then begin
      if EOS then
        Result := True
      else begin
        t.Free;
        t := nil;
      end;
      break;
    end;
    if (c in s) then begin
      t.Data := t.Data + c;
      ConsumeChar;
    end else begin
      Result := True;
      break;
    end;
  until False;
  if Result then begin
    Assert(Assigned(t));
  end else begin
    Assert(not Assigned(t));
  end;
end;

function TTokenizer.SkipUntilCompilerDirective: TToken;
var
  c: Char;
begin
  Result := nil;
  repeat
    if GetChar(c) then
      case c of
        '{':
          begin
            Result := ReadCommentType1;
            CheckForDirective(Result);
            if Result.MyType = TOK_DIRECTIVE then break;
            FreeAndNil(Result);
          end;
        '(':
          begin
            if PeekChar(c) and (c = '*') then
            begin
              ConsumeChar;
              Result := ReadCommentType2;
              CheckForDirective(Result);
              if Result.MyType = TOK_DIRECTIVE then break;
              FreeAndNil(Result);
            end;

            (* If C was not a '*', then we don't consume it here.
               This is important, because C could be #10 (indicates
               newline, so we must Inc(Row)) or even '{' (which could
               indicate compiler directive). And sequences like
               '('#10 and '({$ifdef ...' should work, see
               ../../tests/error_line_number_3.pas and
               ../../tests/ok_not_defined_omit.pas *)

          end;
        #10: Inc(Row);
      end
    else
      DoError('Could not read character', [], 0);
  until False;
end;

end.