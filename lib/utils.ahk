; 踩坑说明：
; 		要编译中文版的时候，一定要把 UTF-8 改成 UTF-8 with BOM
; 		否则会报错并在报错信息里提示乱码，或者错误的报错信息
MakeStahkyMenu( pMenu, searchPath, iPUM, pMenuParams, recursion_CurrentDepth := 0 )
{
	global APP_NAME
	global STAHKY_MAX_DEPTH
	global STAHKY_START_TIME
	global STAHKY_MAX_RUN_TIME

	global ShowOpenCurrentFolder
	global SortFoldersFirst

	if (ShowOpenCurrentFolder)
	{
		; 如果是文件夹且启用了显示当前文件夹选项，
		; 首先显示一个"打开: ..."文件夹选项。更多信息请参见：
		; https://github.com/joedf/stahky/issues/20
		if (SubStr(searchPath, 1-2) == "\*")
		{
			currentDirItem := { "name": "打开此文件夹..."
				,"path": SubStr(searchPath, 1, 0-2)
				,"icon": "shell32.dll:4" }
			pMenu.Add(currentDirItem)
			pMenu.Add() ; 添加分隔符
		}
	}

	if (SortFoldersFirst)
	{
		; 先处理文件夹
		Loop, %searchPath%, 2
		{
			MakeStahkyMenu_subroutine( pMenu, A_LoopFileFullPath, iPUM, pMenuParams, recursion_CurrentDepth )
		}

		; 再处理文件
		Loop, %searchPath%, 0
		{
			MakeStahkyMenu_subroutine( pMenu, A_LoopFileFullPath, iPUM, pMenuParams, recursion_CurrentDepth )
		}
	}
	else
	{
		; 按正常顺序，字母/自然顺序
		Loop, %searchPath%, 1
		{
			MakeStahkyMenu_subroutine( pMenu, A_LoopFileFullPath, iPUM, pMenuParams, recursion_CurrentDepth )
		}
	}

	return pMenu
}

MakeStahkyMenu_subroutine( pMenu, fPath, iPUM, pMenuParams, recursion_CurrentDepth := 0 )
{
	global APP_NAME
	global STAHKY_MAX_DEPTH
	global STAHKY_START_TIME
	global STAHKY_MAX_RUN_TIME

	; 假设我们获取的是fPath中的完整路径

	; 检查菜单创建是否耗时过长，避免处理非常大的文件夹！
	runtime:=(A_TickCount - STAHKY_START_TIME)
	if (runtime > 2000) ; 错误？除非有工具提示否则不起作用？
		ToolTip %APP_NAME% 正在加载... %runtime%
	if (runtime > STAHKY_MAX_RUN_TIME) {
		ToolTip

		MsgBox, 4112, ,
		(Ltrim Join`s
		Stahky运行时间过长！请确保不要包含任何过大的文件夹。
		考虑在您的stahky文件夹中包含指向大型文件夹的快捷方式。
		`n`n最新文件：`n%fPath%`n`n执行时间：%runtime% 毫秒`n程序将立即终止。
		)
		ExitApp
	}

	FileGetAttrib, fileAttrib, % fPath
	if InStr(fileAttrib, "H") ; 跳过任何H（隐藏）文件
		return pMenu ; 跳过此文件，继续处理下一个
	SplitPath,fPath,,,fExt,fNameNoExt

	; 支持像.gitignore、LICENSE这样的文件名
	if (!fNameNoExt)
		fNameNoExt := "." . fExt

	; 支持带有`&`的文件名，这样它们不会变成ALT+字母快捷键并隐藏`&`字符
	fNameNoExt := StrReplace(fNameNoExt,"&","&&")

	; 自动获取合适的图标（如果可能）
	OutIconChoice := getItemIcon(fPath)

	; 设置菜单项的元数据
	mItem := { "name": fNameNoExt
		,"path": fPath
		,"icon": OutIconChoice }

	; 处理任何子菜单
	if fExt in lnk
	{
		; 将stahky文件显示为子菜单
		if (OutTarget := isStahkyFile(fPath)) {

			; 无法从stahky文件配置中获取，因此使用lnk的参数假设目标文件夹
			if !FileExist(OutTarget) {
				FileGetShortcut,%fPath%,,,OutArgs
				OutTarget := Trim(OutArgs,""""`t)
			}

			; 创建并附加stahky子菜单，并限制递归深度
			if (recursion_CurrentDepth < STAHKY_MAX_DEPTH)
			{
				; 递归进入子stahky菜单
				; 不使用"%A_ThisFunc%"，以支持从"MakeStahkyMenu"而不是"MakeStahkyMenu_subroutine"进行可选排序
				MakeStahkyMenu( mItem["submenu"] := iPUM.CreateMenu( pMenuParams )
					,OutTarget . "\*"
					,iPUM
					,pMenuParams
					,recursion_CurrentDepth+1  )
			} else {
				maxStahkyWarningMenu := (mItem["submenu"] := iPUM.CreateMenu( pMenuParams ))
				maxStahkyWarningMenu.Add({ "name": "Stahky菜单过多！(最大 = " . STAHKY_MAX_DEPTH . ")"
					,"disabled": true
					,"icon": "shell32.dll:77" })
			}
		}
	}
	else if (InStr(fileAttrib,"D")) ; 将非快捷方式的文件夹显示为子菜单
	{
		; 递归进入文件夹
		; 不使用"%A_ThisFunc%"，以支持从"MakeStahkyMenu"而不是"MakeStahkyMenu_subroutine"进行可选排序
		MakeStahkyMenu( mItem["submenu"] := iPUM.CreateMenu( pMenuParams )
					,fPath . "\*"
					,iPUM
					,pMenuParams
					,recursion_CurrentDepth )
	}

	; 将菜单项添加到父菜单
	pMenu.add( mItem )

	return pMenu
}

makeStahkyFile(iPath, configFile:="") {
	global APP_NAME
	global STAHKY_EXT
	global G_STAHKY_ARG
	global G_STAHKY_ARG_CFG

	; 假设我们有一个文件夹并获取其名称
	SplitPath,iPath,outFolderName
	; 在与Stahky相同的文件夹中创建快捷方式
	LinkFile := A_ScriptDir . "\" . outFolderName . "." . STAHKY_EXT

	; 检查可选的配置文件参数
	cfgParam := ""
	if (StrLen(configFile) > 0 and isSettingsFile(configFile)) {
		cfgFullPath := NormalizePath(configFile)
		; 基本格式: /config "我的/配置文件/路径/这里.ini"
		cfgParam := G_STAHKY_ARG_CFG . " " . """" . cfgFullPath . """"
	}

	; 编译版本与脚本版本（使用已安装的AHK）的快捷方式不同
	if (A_IsCompiled) {
		FileCreateShortcut, %A_ScriptFullPath%, %LinkFile%, %A_ScriptDir%, %G_STAHKY_ARG% "%iPath%" %cfgParam%
	} else {
		FileCreateShortcut, %A_AhkPath%, %LinkFile%, %A_ScriptDir%,"%A_ScriptFullPath%" %G_STAHKY_ARG% "%iPath%" %cfgParam%
	}

	MsgBox, 64, 已创建新的Stahky, 已在此处创建可固定的快捷方式: `n%LinkFile%
}

isStahkyFile(fPath) {
	global APP_NAME
	global G_STAHKY_ARG

	SplitPath,fPath,,,_ext
	if _ext in lnk
	{
		FileGetShortcut,%fPath%,,,outArgs
		args := StrSplit(outArgs,A_Space)
		for n, arg in args
		{
			if (arg == G_STAHKY_ARG) {
				;MsgBox, 48, , 这是一个Stahky文件!
				/*
				以脚本方式运行示例:
					"C:\Program Files\AutoHotkey\v1.1.37.02\AutoHotkeyU64.exe" 
					"C:\Users\joedf\code\stahky\stahky.ahk"
					/stahky "C:\Users\joedf\code\stahky\~MY-LI~1"
					/config "C:\Users\joedf\code\stahky\~stahky3.ini"
				
				以编译方式运行示例:
					C:\Users\joedf\code\stahky\stahky.exe
					/stahky "C:\Users\joedf\code\stahky\~my-links"
					/config "C:\Users\joedf\code\stahky\stahky.ini"
				*/
				; 可以假设参数后面的路径是用引号包裹的
				; 因为我们现在将所有参数路径都用引号包裹...
				s1 := InStr(outArgs, " " . G_STAHKY_ARG . " """) + StrLen(G_STAHKY_ARG) + 3
				s2 := InStr(outArgs, """", false, s1)
				path := Trim(SubStr(outArgs,s1, s2-s1),"""")
				if FileExist(path)
					return path
				return true
			}
		}
	}
	return false
}

isSettingsFile(fPath) {
	global APP_NAME
	if FileExist(fPath)
	{
		SplitPath, fPath , , , fileExtension
		; 检查是否是现有的INI文件
		if InStr(fileExtension, "ini")
		{
			IniRead, outSection, %fPath%, %APP_NAME%
			if StrLen(outSection) > 2
				return True
		}
	}
	return False
}

loadSettings(SCFile) {
	global
	; 获取任务栏颜色
	TaskbarColor := getTaskbarColor()

	; 计算默认颜色
	TaskbarSColor := lightenColor(TaskbarColor)
	TaskbarTColor := contrastBW(TaskbarSColor)

	; 加载值
	IniRead, offsetX, %SCFile%,%APP_NAME%,offsetX,0
	IniRead, offsetY, %SCFile%,%APP_NAME%,offsetY,0
	IniRead, icoSize, %SCFile%,%APP_NAME%,iconSize,24
	IniRead, STAHKY_MAX_RUN_TIME, %SCFile%,%APP_NAME%,STAHKY_MAX_RUN_TIME,3500
	STAHKY_MAX_RUN_TIME := Max(1000,Min(STAHKY_MAX_RUN_TIME,10000)) ; 最小等待/运行时间1秒，最大10秒
	IniRead, STAHKY_MAX_DEPTH, %SCFile%,%APP_NAME%,STAHKY_MAX_DEPTH,5
	IniRead, SortFoldersFirst, %SCFile%,%APP_NAME%,SortFoldersFirst,0
	IniRead, useDPIScaleRatio, %SCFile%,%APP_NAME%,useDPIScaleRatio,1
	IniRead, exitAfterFolderOpen, %SCFile%,%APP_NAME%,exitAfterFolderOpen,1
	IniRead, ShowOpenCurrentFolder, %SCFile%,%APP_NAME%,ShowOpenCurrentFolder,0
	IniRead, ShowAtMousePosition, %SCFile%,%APP_NAME%,ShowAtMousePosition,0
	IniRead, menuTextMargin, %SCFile%,%APP_NAME%,menuTextMargin,85
	IniRead, menuMarginX, %SCFile%,%APP_NAME%,menuMarginX,4
	IniRead, menuMarginY, %SCFile%,%APP_NAME%,menuMarginY,4
	IniRead, bgColor, %SCFile%,%APP_NAME%,menuBGColor, % TaskbarColor ;0x101010
	IniRead, sbgColor, %SCFile%,%APP_NAME%,menuSelectedBGColor, % TaskbarSColor ;0x272727
	IniRead, stextColor, %SCFile%,%APP_NAME%,menuSelectedTextColor, % TaskbarTColor ; 基于亮度/对比度公式的黑白颜色
	IniRead, textColor, %SCFile%,%APP_NAME%,menuTextColor, % TaskbarTColor
	IniRead, PUM_flags, %SCFile%,%APP_NAME%,PUM_flags,hleft
	; 字体选项
	IniRead, fontName, %SCFile%,%APP_NAME%,fontName,Segoe UI
	IniRead, fontSize, %SCFile%,%APP_NAME%,fontSize,9
	IniRead, fontWeight, %SCFile%,%APP_NAME%,fontWeight,400
	IniRead, fontItalic, %SCFile%,%APP_NAME%,fontItalic,0
	IniRead, fontStrike, %SCFile%,%APP_NAME%,fontStrike,0
	IniRead, fontUnderline, %SCFile%,%APP_NAME%,fontUnderline,0
}

saveSettings(SCFile) {
	global
	; 保存值
	IniWrite, % offsetX, %SCFile%,%APP_NAME%,offsetX
	IniWrite, % offsetY, %SCFile%,%APP_NAME%,offsetY
	IniWrite, % icoSize, %SCFile%,%APP_NAME%,iconSize
	IniWrite, % STAHKY_MAX_RUN_TIME, %SCFile%,%APP_NAME%,STAHKY_MAX_RUN_TIME
	IniWrite, % STAHKY_MAX_DEPTH, %SCFile%,%APP_NAME%,STAHKY_MAX_DEPTH
	IniWrite, % SortFoldersFirst, %SCFile%,%APP_NAME%,SortFoldersFirst
	IniWrite, % useDPIScaleRatio, %SCFile%,%APP_NAME%,useDPIScaleRatio
	IniWrite, % ShowOpenCurrentFolder, %SCFile%,%APP_NAME%,ShowOpenCurrentFolder
	IniWrite, % ShowAtMousePosition, %SCFile%,%APP_NAME%,ShowAtMousePosition
	IniWrite, % exitAfterFolderOpen, %SCFile%,%APP_NAME%,exitAfterFolderOpen
	IniWrite, % menuTextMargin, %SCFile%,%APP_NAME%,menuTextMargin
	IniWrite, % menuMarginX, %SCFile%,%APP_NAME%,menuMarginX
	IniWrite, % menuMarginY, %SCFile%,%APP_NAME%,menuMarginY
	IniWrite, % bgColor, %SCFile%,%APP_NAME%,menuBGColor
	IniWrite, % sbgColor, %SCFile%,%APP_NAME%,menuSelectedBGColor
	IniWrite, % stextColor, %SCFile%,%APP_NAME%,menuSelectedTextColor
	IniWrite, % textColor, %SCFile%,%APP_NAME%,menuTextColor
	IniWrite, % PUM_flags, %SCFile%,%APP_NAME%,PUM_flags
	; 字体选项
	IniWrite, % fontName, %SCFile%,%APP_NAME%,fontName
	IniWrite, % fontSize, %SCFile%,%APP_NAME%,fontSize
	IniWrite, % fontWeight, %SCFile%,%APP_NAME%,fontWeight
	IniWrite, % fontItalic, %SCFile%,%APP_NAME%,fontItalic
	IniWrite, % fontStrike, %SCFile%,%APP_NAME%,fontStrike
	IniWrite, % fontUnderline, %SCFile%,%APP_NAME%,fontUnderline
}

lightenColor(cHex, L:=2.64) {
	R := (L * (10+(cHex>>16 & 0xFF))) & 0xFF
	G := (L * (10+(cHex>>8 & 0xFF))) & 0xFF
	B := (L * (10+(cHex & 0xFF))) & 0xFF
	return Format("0x{:X}", (R<<16 | G<<8 | B<<0) )
}
contrastBW(c) { ; 基于 https://gamedev.stackexchange.com/a/38561/48591
	R := 0.2126 * (c>>16 & 0xFF) / 0xFF
	G := 0.7152 * (c>>8 & 0xFF) / 0xFF
	B := 0.0722 * (c & 0xFF) / 0xFF
	luma := R+G+B
	return (luma > 0.35) ? 0x000000 : 0xFFFFFF
}

getTaskbarColor() {
	; 获取任务栏位置/大小信息
	WinGetPos tx, ty, tw, th, ahk_class Shell_TrayWnd

	; 计算像素位置
	tPix_x := tx + tw - 2
	tPix_y := ty + th - 2

	; 获取颜色并返回
	PixelGetColor, TaskbarColor, % tPix_x, % tPix_y, RGB
	return TaskbarColor
}

GetMonitorMouseIsIn() {
	; 代码来自 Maestr0
	; https://www.autohotkey.com/boards/viewtopic.php?p=235163#p235163

	; 首先获取鼠标坐标
	Coordmode, Mouse, Screen	; 使用屏幕坐标系，以便我们可以将坐标与sysget信息进行比较
	MouseGetPos, Mx, My

	SysGet, MonitorCount, 80	; 显示器数量，这样我们就知道有多少个显示器以及需要循环的次数
	Loop, %MonitorCount%
	{
		SysGet, mon%A_Index%, Monitor, %A_Index%	; "Monitor"将获取显示器的整个桌面空间，包括任务栏
		if ( Mx >= mon%A_Index%left ) && ( Mx < mon%A_Index%right ) && ( My >= mon%A_Index%top ) && ( My < mon%A_Index%bottom )
		{
			ActiveMon := A_Index
			break
		}
	}
	return ActiveMon
}

getOptimalMenuPos(mx, my) {
	; 基于stacky的代码，但支持多显示器
	; https://github.com/joedf/stahky/issues/21#issuecomment-2722264863
	hMonitor := GetMonitorMouseIsIn()
	SysGet, rWorkArea, MonitorWorkArea, %hMonitor%

	pos_x := mx, pos_y := my
	if (pos_x < rWorkAreaLeft) {
		pos_x := rWorkAreaLeft - 1
	} else if (pos_x > rWorkAreaRight) {
		pos_x := rWorkAreaRight - 1
	}

	if (pos_y < rWorkAreaTop) {
		pos_y := rWorkAreaTop - 1
	} else if (pos_y > rWorkAreaBottom) {
		pos_y := rWorkAreaBottom - 1
	}
	
	; 经过测试，这些标志似乎不需要
	; SysGet, menuDropAlign, % (SM_MENUDROPALIGNMENT := 40)
	; flags := menuDropAlign | (TPM_LEFTBUTTON := 0)
	
	return { x: pos_x, y: pos_y, flags: flags }
}

getItemIcon(fPath) {
	SplitPath,fPath,,,fExt
	FileGetAttrib,fAttr,%fPath%

	OutIconChoice := ""

	; 支持可执行二进制文件
	if fExt in exe,dll
		OutIconChoice := fPath  . ":0"

	; 支持Windows快捷方式/链接文件 *.lnk
	if fExt in lnk
	{
		FileGetShortcut, %fPath%, OutTarget,,,, OutIcon, OutIconNum
		SplitPath,OutTarget,,,OutTargetExt
		if OutTargetExt in exe,dll
			OutIconChoice := OutTarget  . ":0"
		if (OutIcon && OutIconNum)
			OutIconChoice := OutIcon  . ":" . (OutIconNum-1)
		else {
			; 支持指向没有自定义图标集的文件夹的快捷方式（默认）
			FileGetAttrib,_attr,%OutTarget%
			if (InStr(_attr,"D")) {
				; 显示默认图标而不是空白文件图标
				OutIconChoice := "imageres.dll:4"
			}
		}
	}
	; 支持Windows互联网快捷方式文件 *.url
	else if fExt in url
	{
		IniRead, OutIcon, %fPath%, InternetShortcut, IconFile
		IniRead, OutIconNum, %fPath%, InternetShortcut, IconIndex, 0
		if FileExist(OutIcon)
			OutIconChoice := OutIcon  . ":" . OutIconNum
	}

	; 支持文件夹图标
	if (InStr(fAttr,"D"))
	{
		OutIconChoice := "shell32.dll:4"

		; 自定义文件夹可能包含一个名为desktop.ini的隐藏系统文件
		_dini := fPath . "\desktop.ini"
		; https://msdn.microsoft.com/en-us/library/cc144102.aspx

		; 情况1
		; [.ShellClassInfo]
		; IconResource=C:\WINDOWS\System32\SHELL32.dll,130
		IniRead,_ico,%_dini%,.ShellClassInfo,IconResource,0
		if (_ico) {
			lastComma := InStr(_ico,",",0,0)
			OutIconChoice := Substr(_ico,1,lastComma-1) . ":" . substr(_ico,lastComma+1)
		} else {
			; 情况2
			; [.ShellClassInfo]
			; IconFile=C:\WINDOWS\System32\SHELL32.dll
			; IconIndex=130
			IniRead,_icoFile,%_dini%,.ShellClassInfo,IconFile,0
			IniRead,_icoIdx,%_dini%,.ShellClassInfo,IconIndex,0
			if (_icoFile)
				OutIconChoice := _icoFile . ":" . _icoIdx
		}
	}

	; 支持关联的文件类型
	else if (StrLen(OutIconChoice) < 4)
		OutIconChoice := getExtIcon(fExt)

	return OutIconChoice
}

getExtIcon(Ext) { ; 修改自 AHK_User - https://www.autohotkey.com/boards/viewtopic.php?p=297834#p297834
	I1 := I2:= ""
	RegRead, from, HKEY_CLASSES_ROOT, .%Ext%
	RegRead, DefaultIcon, HKEY_CLASSES_ROOT, %from%\DefaultIcon
	StringReplace, DefaultIcon, DefaultIcon, `",,all
	StringReplace, DefaultIcon, DefaultIcon, `%SystemRoot`%, %A_WinDir%,all
	StringReplace, DefaultIcon, DefaultIcon, `%ProgramFiles`%, %A_ProgramFiles%,all
	StringReplace, DefaultIcon, DefaultIcon, `%windir`%, %A_WinDir%,all
	StringSplit, I, DefaultIcon, `,
	DefaultIcon := I1 ":" RegExReplace(I2, "[^\d-]+") ;清理索引号，但支持负数

	if (StrLen(DefaultIcon) < 4) {
		; 默认文件图标，如果其他方法都失败
		DefaultIcon := "shell32.dll:0"

		; Windows默认使用OpenCommand（如果可用）
		RegRead, OpenCommand, HKEY_CLASSES_ROOT, %from%\shell\open\command
		if (OpenCommand) {
			OpenCommand := StrSplit(OpenCommand,"""","""`t`n`r")[2]
			DefaultIcon := OpenCommand . ":0"
		}
	}

	return DefaultIcon
}

NormalizePath(path) { ; 来自 AHK v1.1.37.02 文档
	cc := DllCall("GetFullPathName", "str", path, "uint", 0, "ptr", 0, "ptr", 0, "uint")
	VarSetCapacity(buf, cc*2)
	DllCall("GetFullPathName", "str", path, "uint", cc, "str", buf, "ptr", 0)
	return buf
}

FirstRun_Trigger() {
	global G_FirstRun_Trigger
	global APP_NAME
	global APP_VERSION
	global APP_REVISION

	; 防止程序在显示此对话框时自动退出
	G_FirstRun_Trigger := true

	Gui, AboutDialog:New, +LastFound +AlwaysOnTop +ToolWindow
	Gui, AboutDialog:Margin, 10, -7
	Gui, Color, white
	;@Ahk2Exe-IgnoreBegin
	Gui, Add, Picture, x12 y9 w48 h48, %A_ScriptDir%\res\app.ico
	;@Ahk2Exe-IgnoreEnd
	/*@Ahk2Exe-Keep
	Gui, Add, Picture, x12 y9 w48 h48 Icon1, %A_ScriptFullPath%
	*/
	Gui, Font, s20 bold, Segoe UI
	Gui, Add, Text, x72 y2, %APP_NAME%
	Gui, Font, s9 norm
	Gui, Add, Text, x+4 yp+15, v%APP_VERSION%
	Gui, Add, Text, x72 yp+18 R2, 由 joedf 开发
	Gui, Add, Text, , 修订日期: %APP_REVISION%
	Gui, Add, Text, R2, 基于 MIT 许可证发布
	Gui, Add, Link, R2, 特别感谢 <a href="https://www.autohotkey.com/board/topic/73599-ahk-l-pum-owner-drawn-object-based-popup-menu">Deo 的 PUM.ahk</a>
	Gui, Add, Text, , 第一次使用？
	Gui, Add, Link, , <a href="https://github.com/joedf/stahky">https://github.com/joedf/stahky</a>
	Gui, Add, Link, , 或者软件根目录的<a href=".\readme.md">README.md</a>文件
	Gui, AboutDialog:Margin, , 10
	Gui, Show, , 关于 %APP_NAME%
	return

	AboutDialogGuiEscape:
	AboutDialogGuiClose:
	ExitApp
}
