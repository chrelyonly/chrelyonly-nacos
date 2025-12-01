@echo off
chcp 65001 >nul
echo 正在启动 Nacos...
set "JAVA=D:\dev\dev\sdk\java\java17\bin\java.exe"

setlocal enabledelayedexpansion

set BASE_DIR=%~dp0
rem 为避免路径中含空格问题，添加了双引号
rem 去掉最后5个字符（即 \bin\）获取基础目录
set BASE_DIR="%BASE_DIR:~0,-5%"

set CUSTOM_SEARCH_LOCATIONS=file:%BASE_DIR%/conf/

set MODE="standalone"
set FUNCTION_MODE="all"
set SERVER=nacos-server
set MODE_INDEX=-1
set FUNCTION_MODE_INDEX=-1
set SERVER_INDEX=-1
set EMBEDDED_STORAGE_INDEX=-1
set EMBEDDED_STORAGE=""
set DEPLOYMENT_INDEX=-1
set DEPLOYMENT="merged"

rem 遍历命令行参数，记录特定参数的位置
set i=0
for %%a in (%*) do (
    if "%%a" == "-m" ( set /a MODE_INDEX=!i!+1 )
    if "%%a" == "-f" ( set /a FUNCTION_MODE_INDEX=!i!+1 )
    if "%%a" == "-s" ( set /a SERVER_INDEX=!i!+1 )
    if "%%a" == "-p" ( set /a EMBEDDED_STORAGE_INDEX=!i!+1 )
    if "%%a" == "-d" ( set /a DEPLOYMENT_INDEX=!i!+1 )
    set /a i+=1
)

rem 根据位置获取实际参数值
set i=0
for %%a in (%*) do (
    if %MODE_INDEX% == !i! ( set MODE="%%a" )
    if %FUNCTION_MODE_INDEX% == !i! ( set FUNCTION_MODE="%%a" )
    if %SERVER_INDEX% == !i! (set SERVER="%%a")
    if %EMBEDDED_STORAGE_INDEX% == !i! (set EMBEDDED_STORAGE="%%a")
    if %DEPLOYMENT_INDEX% == !i! (set DEPLOYMENT="%%a")
    set /a i+=1
)

rem 处理必填配置
call :Process_required_config "nacos.core.auth.plugin.nacos.token.secret.key" %BASE_DIR%\conf\application.properties
call :Process_required_config "nacos.core.auth.server.identity.key" %BASE_DIR%\conf\application.properties
call :Process_required_config "nacos.core.auth.server.identity.value" %BASE_DIR%\conf\application.properties

rem 如果 Nacos 启动模式为 standalone
if %MODE% == "standalone" (
    echo "Nacos 正在以独立模式启动"
	set "NACOS_OPTS=-Dnacos.standalone=true"
    if "%CUSTOM_NACOS_MEMORY%"=="" ( set "CUSTOM_NACOS_MEMORY=-Xms512m -Xmx512m -Xmn256m" )
    set "NACOS_JVM_OPTS=-Dlogging.level.root=OFF -Dlogging.level.org.springframework=OFF %CUSTOM_NACOS_MEMORY%"

)

rem 如果 Nacos 启动模式为 cluster
if %MODE% == "cluster" (
    echo "Nacos 正在以集群模式启动"
	if %EMBEDDED_STORAGE% == "embedded" (
	    set "NACOS_OPTS=-DembeddedStorage=true"
	)
    if "%CUSTOM_NACOS_MEMORY%"=="" ( set "CUSTOM_NACOS_MEMORY=-Xms2g -Xmx2g -Xmn1g -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=320m" )
    set "NACOS_JVM_OPTS=-server %CUSTOM_NACOS_MEMORY% -XX:-OmitStackTraceInFastThrow -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=%BASE_DIR%\logs\java_heapdump.hprof -XX:-UseLargePages"
)

rem 设置 Nacos 的功能模式
if %FUNCTION_MODE% == "config" (
    set "NACOS_OPTS=%NACOS_OPTS% -Dnacos.functionMode=config"
)

if %FUNCTION_MODE% == "naming" (
    set "NACOS_OPTS=%NACOS_OPTS% -Dnacos.functionMode=naming"
)

rem 设置 Nacos 启动选项
set "NACOS_OPTS=%NACOS_OPTS% -Dnacos.deployment.type=%DEPLOYMENT%"
set "NACOS_OPTS=%NACOS_OPTS% -Dloader.path=%BASE_DIR%/plugins,%BASE_DIR%/plugins/health,%BASE_DIR%/plugins/cmdb,%BASE_DIR%/plugins/selector"
set "NACOS_OPTS=%NACOS_OPTS% -Dnacos.home=%BASE_DIR%"
set "NACOS_OPTS=%NACOS_OPTS% -jar %BASE_DIR%\target\%SERVER%.jar"

rem 设置 Nacos Spring 配置文件路径
set "NACOS_CONFIG_OPTS=--spring.config.additional-location=%CUSTOM_SEARCH_LOCATIONS%"

rem 设置 Nacos 日志配置文件路径
set "NACOS_LOG4J_OPTS=--logging.config=%BASE_DIR%/conf/nacos-logback2.xml"

rem 拼接启动命令
set COMMAND="%JAVA%" %NACOS_JVM_OPTS% %NACOS_OPTS% %NACOS_CONFIG_OPTS% %NACOS_LOG4J_OPTS% nacos.nacos %*

rem 启动 Nacos
%COMMAND%

pause

goto :EOF

:Process_required_config
    setlocal
    set "key_pattern=%~1"
    set "target_file=%~2"
    set "target_file=!target_file:"=!"

    set "escaped_key=%key_pattern:.=\.%"

    findstr /R /C:"^%escaped_key%[= ].*" "%target_file%" >nul
    if %errorlevel% == 0 (
        rem 检查 key 是否为空
        for /f "usebackq tokens=1,2 delims==" %%a in ("%target_file%") do (
            if "%%a"=="%key_pattern%" if "%%b"=="" (
                rem 值为空，要求用户输入
                set /p "input_val=%key_pattern% 值为空，请输入: "
                set "temp_file=%TEMP%\temp_%RANDOM%.tmp"
                set "key_pattern_with_equal=!key_pattern!="

                for /f "usebackq delims=" %%a in ("!target_file!") do (
                    set "line=%%a"
                    set "line=!line: =!"
                    if "!line!"=="!key_pattern_with_equal!" (
                        echo %%a!input_val!>>"!temp_file!"
                    ) else (
                        echo %%a>>"!temp_file!"
                    )
                )
                move /Y "!temp_file!" "!target_file!" >nul
                echo %key_pattern% 已更新，新值为: %input_val%
                findstr /R "^%escaped_key%" "%target_file%"
                echo ----------------------------------
                exit /b
            )
        )
    )
    endlocal
