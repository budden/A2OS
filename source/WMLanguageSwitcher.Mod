MODULE WMLanguageSwitcher; (** AUTHOR "Yaroslav Romanchenko rapturize@gmail.com"; PURPOSE "Simple language switcher example"; *)

IMPORT
	Commands, WMMessages, WMWindowManager, WMComponents, Localization, Options;
		
PROCEDURE SetLanguage*(ctx: Commands.Context);
VAR
	options : Options.Options;
	lang : ARRAY 3 OF CHAR;
	ext : WMComponents.LanguageExtension;
	msg : WMMessages.Message;
	lng : Localization.Language;
	mng : WMWindowManager.WindowManager;
BEGIN
	NEW(options);
	options.Add("l", "lang", Options.String);
	IF options.Parse(ctx.arg, ctx.out) & options.GetString("lang", lang) THEN
		NEW(ext); NEW(ext.languages, 1);
		lng.code := lang;
		(*Localization.SetLanguage(lng);*)
		ext.languages[0] := lng;
		msg.ext := ext;
		msg.msgType := WMMessages.MsgSetLanguage;
		mng := WMWindowManager.GetDefaultManager();
		ctx.out.String("WMLanguageSwitcher: Setting language: ");
		ctx.out.String(lang);
		ctx.out.Ln;
		mng.Broadcast(msg);
	ELSE
		ctx.out.String("WMLanguageSwitcher: Error: Language code expected.");
		ctx.out.Ln
	END;
END SetLanguage;

BEGIN

END WMLanguageSwitcher.

WMLanguageSwitcher.SetLanguage -l=ru ~
WMLanguageSwitcher.SetLanguage -l=en ~

System.Free WMLanguageSwitcher ~