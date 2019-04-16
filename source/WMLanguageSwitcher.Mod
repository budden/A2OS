MODULE WMLanguageSwitcher; (** AUTHOR "Yaroslav Romanchenko rapturize@gmail.com"; PURPOSE "Simple language switcher example"; *)

IMPORT
	Commands, Options, Localization,
	Components := WMComponents, Messages := WMMessages, WM := WMWindowManager;
		
PROCEDURE SetLanguage*(ctx: Commands.Context);
VAR
	options : Options.Options;
	language : Localization.Language;
	extension : Components.LanguageExtension;
	message : Messages.Message;
	manager : WM.WindowManager;
BEGIN
	NEW(options);
	options.Add("l", "lang", Options.String);
	IF options.Parse(ctx.arg, ctx.out) & options.GetString("lang", language.code) THEN
		ctx.out.String("WMLanguageSwitcher: Setting language: ");
		ctx.out.String(language.code);
		ctx.out.Ln;
		Localization.SetLanguage(language);
		message.msgType := Messages.MsgSetLanguage;
		NEW(extension);
		NEW(extension.languages, 1);
		extension.languages[0] := language;
		message.ext := extension;
		manager := WM.GetDefaultManager();
		manager.Broadcast(message);
	ELSE
		ctx.out.String("WMLanguageSwitcher: Error: Language code expected.");
		ctx.out.Ln
	END;
END SetLanguage;

BEGIN

END WMLanguageSwitcher.

WMLanguageSwitcher.SetLanguage -l=en ~
WMLanguageSwitcher.SetLanguage -l=ru ~
WMLanguageSwitcher.SetLanguage -l=uk ~
WMLanguageSwitcher.SetLanguage -l=de ~

System.Free WMLanguageSwitcher WMClock ~