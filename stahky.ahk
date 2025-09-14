; 踩坑说明：
; 		要编译中文版的时候，一定要把 UTF-8 改成 UTF-8 with BOM
; 		否则会报错并在报错信息里提示乱码，或者错误的报错信息

; ===================================================================================

; stahky
; 作者: joedf - 开始于 2020.07.10
;
; 灵感来源于 Stacky (作者: Pawel Turlejski)
; https://github.com/pawelt/stacky
; https://web.archive.org/web/20130927190146/http://justafewlines.com/2013/04/stacky/


; https://www.autohotkey.com/docs/misc/Performance.htm
#NoEnv
SetBatchLines -1
ListLines Off

#NoTrayIcon
#SingleInstance, Force

; 确保如果工作目录不同时，从正确的文件夹使用库
#Include %A_ScriptDir%

#Include lib\utils.ahk

; 使用 Deo 的 PUM
#Include lib\PUM_API.ahk
#Include lib\PUM.ahk

APP_NAME := "stahky"
APP_VERSION := "0.3.9.1"
APP_REVISION := "2025/03/19"

;@Ahk2Exe-SetName stahky
;@Ahk2Exe-SetVersion 0.3.9.1
;@Ahk2Exe-SetDescription 基于 AutoHotkey (AHK) 为 Windows 10 实现的 stacky 变体
;@Ahk2Exe-SetCopyright (c) 2025 joedf.github.io
;@Ahk2Exe-SetCompanyName joedf.github.io
;@Ahk2Exe-SetMainIcon res\app.ico

; 使用 mpress 的技巧，如果不可用也不报错
;@Ahk2Exe-PostExec cmd /c mpress.exe "%A_WorkFileName%" &rem, 0


STAHKY_EXT := APP_NAME . ".lnk"
G_STAHKY_ARG := "/stahky"
G_STAHKY_ARG_CFG := "/config"
StahkyConfigFile := A_ScriptDir "\" APP_NAME ".ini"

; AutoHotkey 所需的行为设置
GroupAdd APP_Self_WinGroup, ahk_id %A_ScriptHwnd%
GroupAdd APP_Self_WinGroup, % "ahk_pid " DllCall("GetCurrentProcessId")
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen
MouseGetPos, mouseX, mouseY

; ================ [ 创建一个快捷方式 Stahky ] ================

; 智能自动创建 *lnk 可固定快捷方式文件，当文件夹被拖到此应用程序上时
if ( A_Args[1] != G_STAHKY_ARG && FileExist(A_Args[1]) )
{
	; 如果未指定配置，则使用默认值
	_runPath := ""
	_configFile := ""

	; 解析参数以查看是否传递了文件夹以及可选的 ini 文件
	for _n, param in A_Args
	{
		; 路径必须存在，无论它是文件还是文件夹
		if FileExist(param)
		{
			; 检查是否给定了一个目录/文件夹，如果是则创建一个新的 stahky
			FileGetAttrib,_t, % param
			if InStr(_t,"D")
			{
				_runPath := param
			}
			else {
				; 否则，我们可能有一个文件...
				; 检查是否指定了设置/配置文件
				if isSettingsFile(param)
				{
					_configFile := param
				} else {
					MsgBox, 48, %APP_NAME% - 错误: 无效的配置文件, 错误: 无法使用无效的配置文件创建 stahky 快捷方式: "%param%"
				}
			}
		}
	}

	; 检查是否获得了有效选项，如果是则创建 stahky 文件
	if StrLen(_runPath) > 0 {
		; 创建 stahky 快捷方式文件
		makeStahkyFile(_runPath, _configFile)
		; 我们完成了！不执行程序的其余部分 ... arrrgg >_<
		ExitApp
	}
}
; 否则，如果我们不处于“创建模式”，则正常进行...

; ======================= [ 运行 Stahky ] =======================

; 检查是否为首次运行，是否显示介绍对话框
G_FirstRun_Trigger := false
if !FileExist(StahkyConfigFile)
	FirstRun_Trigger()

; 获取搜索路径
searchPath := A_WorkingDir . "\*"

; 解析每个参数以查看：
;  1. 是否提供了文件夹或搜索路径
;  2. 是否提供了自定义的 stahky 配置/设置 ini 文件
for _n, param in A_Args
{
	; 检查是否为开关 '/' 参数
	if (SubStr(param, 1, 1) == "/") {
		; 并检查后面是否跟有值
		if (A_Args.Length() > _n) {
			value := A_Args[_n+1]

			; 解析搜索路径参数
			if InStr(param, G_STAHKY_ARG)
			{
				if FileExist(value) {
					; 如果可用，使用 Stahky 快捷方式文件的路径
					FileGetAttrib,_t, % value
					if InStr(_t,"D") {
						searchPath := value . "\*"
					} else {
						; 如果不是文件夹，警告用户并退出 .... wut -,-
						MsgBox, 48, %APP_NAME% - 错误: 无效的 stahky 配置, 错误: 无法启动 stahky，因为找不到以下目标文件夹:`n"%value%"
						ExitApp
					}
				}
			}
			; 解析配置文件参数
			else if InStr(param, G_STAHKY_ARG_CFG)
			{
				_cfgPath := NormalizePath(value)
				if isSettingsFile(_cfgPath)
				{
					StahkyConfigFile := _cfgPath
				} else {
					; 如果配置文件无效，我们简单地继续执行并
					; 忽略给定的配置。如果可能，我们使用默认的配置文件。
				}
			}
		} else {
			MsgBox, 48, %APP_NAME% - 错误: 无效的 stahky 参数, 错误: 无法启动 stahky，参数 "%param%" 没有值。
			ExitApp
		}
	}
}

; 获取/更新设置、颜色、位置偏移量等...
loadSettings(StahkyConfigFile)
saveSettings(StahkyConfigFile)

; 更新高 DPI 显示的值
DPIScaleRatio := 1
if (useDPIScaleRatio) {
	DPIScaleRatio := (A_ScreenDPI / 96)
	icoSize *= DPIScaleRatio
	menuTextMargin *= DPIScaleRatio
	menuMarginX *= DPIScaleRatio
	menuMarginY *= DPIScaleRatio
}

; PUM 菜单项的字体选项
fontOptions := {name: fontName
	,height: fontSize
	,Weight: fontWeight
	,Italic: fontItalic
	,strike: fontStrike
	,Underline: fontUnderline}

; PUM 对象的参数，菜单管理器
pumParams := {"SelMethod" : "fill" ;项目选择方法，可以是 frame 或 fill
	,"selTColor"   : stextColor    ;选中文本颜色
	,"selBGColor"  : sbgColor      ;选中背景颜色，-1 表示反转当前颜色
	,"oninit"      : "PUM_out"     ;当任何菜单即将打开时将被调用的函数
	,"onuninit"    : "PUM_out"     ;当任何菜单即将关闭时将被调用的函数
	,"onselect"    : "PUM_out"     ;当任何项目被鼠标悬停选中时将被调用的函数
	,"onrbutton"   : "PUM_out"     ;当任何项目被右键点击时将被调用的函数
	,"onmbutton"   : "PUM_out"     ;当任何项目被中键点击时将被调用的函数
	,"onrun"       : "PUM_out"     ;当任何项目被左键点击时将被调用的函数
	,"onshow"      : "PUM_out"     ;在使用 Show 方法显示任何菜单之前将被调用的函数
	,"onclose"     : "Pum_out"     ;在从 Show 方法退出之前调用的函数
	,"pumfont"     : fontOptions   ;字体选项，LOGFONT: https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-logfonta
	,mnemonicCMD   : "select"}

; PUM_Menu 参数
menuParams := {"bgcolor" : bgColor ;菜单背景颜色
	, "iconssize" : icoSize        ;菜单中图标的大小
	, "tcolor"    : textColor      ;菜单项的文本颜色
	, "textMargin": menuTextMargin
	, "xmargin"   : menuMarginX
	, "ymargin"   : menuMarginY }

; 创建 PUM 对象的实例，程序中最好只有一个这样的实例
pm := new PUM( pumParams )
; 创建弹出菜单，由具有给定参数的 PUM_Menu 对象表示
menu := pm.CreateMenu( menuParams )

; 记录开始时间以防止运行时间过长而没有视觉反馈
STAHKY_START_TIME := A_TickCount

; 填充 Stahkys!
MakeStahkyMenu(menu, searchPath, pm, menuParams )

; 计算显示菜单的坐标
if (ShowAtMousePosition) {
	menuPos := {x: mouseX, y: mouseY}
	PUM_flags := "" ; 如果使用此模式，则忽略标志
} else {
	; 计算菜单的最佳位置，
	; 无论是在任务栏附近还是作为上下文菜单在其他地方
	menuPos := getOptimalMenuPos(mouseX, mouseY)
}

; 显示 PUM 菜单
item := menu.Show( menuPos.x+offsetX, menuPos.y+offsetY, PUM_flags )

; 在程序结束时销毁所有 PUM 相关对象
pm.Destroy()

; 首次运行已触发 - 不要自动退出
if (!G_FirstRun_Trigger)
	ExitApp
return


; PUM 的右键点击 / rbutton 处理程序不可靠
; 在这里做一些额外的处理
; https://autohotkey.com/board/topic/94970-ifwinactive-reference-running-autohotkey-window/#entry598885
;
; 不需要 #If，因为只有在有菜单或窗口显示时应用程序才会运行
;#IfWinExist ahk_group APP_Self_WinGroup
+#a::
~$*RButton::
	FirstRun_Trigger()
return
;#IfWinExist


; 处理附加的 PUM 事件和操作
PUM_out( msg, obj ) {

	; 正常运行项目
	if (msg == "onrun")
	{
		rPath := obj.path

		; 尝试正常运行/启动
		Run, %rPath%,,UseErrorLevel

		; 如果失败，假设是快捷方式并重试
		if (ErrorLevel) {
			try {
				FileGetShortcut,%rPath%,outTarget,outWrkDir,outArgs
				Run, "%outTarget%" %outArgs%, %outWrkDir%, UseErrorLevel

				; 如果再次失败，可能是 ProgramFiles x86 与 x64 的问题: https://github.com/joedf/stahky/issues/2
				if (ErrorLevel)
				{
					EnvGet, pf64, ProgramW6432
					_outTarget64 := StrReplace(outTarget, A_ProgramFiles, pf64, , 1)
					Run, "%_outTarget64%" %outArgs%, %outWrkDir%
				}
			}
			catch ; 运行失败，提醒用户
			{
				MsgBox, 48,, Error: Could not launch the following (please verify it exists):`n%outTarget%
			}
		}
	}

	; 中键点击时，如果我们有 stahky，则打开文件夹
	if (msg == "onmbutton") {

		; 打开 stahky 的文件夹
		if (_p:=isStahkyFile(obj.path)) {
			if FileExist(_p)
				Run % _p
		}
		else ; 打开当前菜单或子菜单的父文件夹
		{
			SplitPath, % obj.path,,_p
			Run, % _p
		}

		global exitAfterFolderOpen
		if (exitAfterFolderOpen)
			ExitApp
	}

	; 右键点击时，打开关于/首次使用对话框
	if (msg == "onrbutton") {
		FirstRun_Trigger()
	}
}
