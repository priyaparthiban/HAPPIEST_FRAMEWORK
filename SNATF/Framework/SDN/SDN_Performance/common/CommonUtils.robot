*** Settings ***
Documentation     General Utils library. This library has broad scope, it can be used by any robot system tests.
Library           SSHLibrary
Library           HttpLibrary.HTTP
Library           String
Library           DateTime
Library           Process
Library           Collections
Library           RequestsLibrary
Library           OperatingSystem
Library           ${CURDIR}/CommonUtilLibrary.py
Resource          ${CURDIR}/CommonSSHKeywords.robot
Resource          ${CURDIR}/CommonTemplatedRequests.robot
Variables         ../../../../TestRepository/Variables/SDN_Performance-GlobalVariables.py
*** Variables ***

*** Keywords ***
Start Mininet
    [Arguments]    ${system}=${TOOLS_SYSTEM_IP}    ${user}=${TOOLS_SYSTEM_USER}    ${password}=${TOOLS_SYSTEM_PASSWORD}    ${prompt}=${DEFAULT_LINUX_PROMPT}    ${timeout}=30s
    [Documentation]    Basic setup/cleanup work that can be done safely before any system
    ...    is run.
    Log    Start the test on the base edition
    Clean Mininet System
    ${mininet_conn_id}=    Open Connection    ${system}    prompt=${prompt}    timeout=${timeout}
    Set Suite Variable    ${mininet_conn_id}
    SSHKeywords.Flexible Mininet Login    user=${user}    password=${password}
    Execute Command    sudo ovs-vsctl set-manager ptcp:6644
    Write    ${start}
    Read Until    mininet>


Stop Mininet
    [Arguments]    ${prompt}=${DEFAULT_LINUX_PROMPT}
    [Documentation]    Cleanup/Shutdown work that should be done at the completion of all
    ...    tests
    Log    Stop the test on the base edition
    Switch Connection    ${mininet_conn_id}
    Read
    Write    exit
    Read Until    ${prompt}
    Close Connection


Check For Specific Number Of Elements At URI
    [Arguments]    ${uri}    ${element}    ${expected_count}    ${session}=session
    [Documentation]    A GET is made to the specified ${URI} and the specific count of a
    ...    given element is done (as supplied by ${element} and ${expected_count})
    ${resp}    RequestsLibrary.Get Request    ${session}    ${uri}
    Log    ${resp.content}
    Should Be Equal As Strings    ${resp.status_code}    200
    Should Contain X Times    ${resp.content}    ${element}    ${expected_count}


Check For Elements At URI
    [Arguments]    ${uri}    ${elements}    ${session}=session
    [Documentation]    A GET is made at the supplied ${URI} and every item in the list of
    ...    ${elements} is verified to exist in the response
    ${resp}    RequestsLibrary.Get Request    ${session}    ${uri}
    Log    ${resp.content}
    Should Be Equal As Strings    ${resp.status_code}    200
    : FOR    ${i}    IN    @{elements}
    \    Should Contain    ${resp.content}    ${i}


Check For Elements Not At URI
    [Arguments]    ${uri}    ${elements}    ${session}=session
    [Documentation]    A GET is made at the supplied ${URI} and every item in the list of
    ...    ${elements} is verified to NOT exist in the response
    ${resp}    RequestsLibrary.Get Request    ${session}    ${uri}
    Log    ${resp.content}
    Should Be Equal As Strings    ${resp.status_code}    200
    : FOR    ${i}    IN    @{elements}
    \    Should Not Contain    ${resp.content}    ${i}


Clean Mininet System
    [Arguments]    ${system}=${TOOLS_SYSTEM_IP}
    Run Command On Mininet    ${system}    sudo mn -c
    Run Command On Mininet    ${system}    sudo ps -elf | egrep 'usr/local/bin/mn' | egrep python | awk '{print "sudo kill -9",$4}' | sh



Clean Up Ovs
    [Arguments]    ${system}=${TOOLS_SYSTEM_IP}
    [Documentation]    Cleans up the OVS instance and remove any existing common known bridges.
    ${output}=    Run Command On Mininet    ${system}    sudo ovs-vsctl list-br
    Log    ${output}
    : FOR    ${i}    IN    ${output}
    \    Run Command On Mininet    ${system}    sudo ovs-vsctl --if-exists del-br ${i}
    Run Command On Mininet    ${system}    sudo ovs-vsctl del-manager


Extract Value From Content
    [Arguments]    ${content}    ${index}    ${strip}=nostrip
    [Documentation]    Will take the given response content and return the value at the given index as a string
    ${value}=    Get Json Value    ${content}    ${index}
    ${value}=    Convert To String    ${value}
    ${value}=    Run Keyword If    '${strip}' == 'strip'    Strip Quotes    ${value}
    [Return]    ${value}


Get Process ID Based On Regex On Remote System
    [Arguments]    ${system}    ${regex_string_to_match_on}    ${user}=${TOOLS_SYSTEM_USER}    ${password}=${EMPTY}    ${prompt}=${DEFAULT_LINUX_PROMPT}    ${prompt_timeout}=30s
    [Documentation]    Uses ps to find a process that matches the supplied regex. Returns the PID of that process
    ...    The ${regex_string_to_match_on} should produce a unique process otherwise the PID returned may not be
    ...    the expected PID
    # doing the extra -v grep in this command to exclude the grep process itself from the output
    ${cmd}=    Set Variable    ps -elf | grep -v grep | grep ${regex_string_to_match_on} | awk '{print $4}'
    ${output}=    Run Command On Remote System    ${system}    ${cmd}    user=${user}    password=${password}    prompt=${prompt}
    ...    prompt_timeout=${prompt_timeout}
    # ${output} contains the system prompt and all we want is the value of the number
    ${pid}=    Fetch From Left    ${output}    \r
    # TODO: Get Process * keywords have perhaps non-standard default credentials.
    # ...    Should there be * On Mininet and * On Controller specializations?
    [Return]    ${pid}


Get Process Thread Count On Remote System
    [Arguments]    ${system}    ${pid}    ${user}=${TOOLS_SYSTEM_USER}    ${password}=${EMPTY}    ${prompt}=${DEFAULT_LINUX_PROMPT}    ${prompt_timeout}=30s
    [Documentation]    Executes the ps command to retrieve the lightweight process (aka thread) count.
    ${cmd}=    Set Variable    ps --no-headers -o nlwp ${pid}
    ${output}=    Run Command On Remote System    ${system}    ${cmd}    user=${user}    password=${password}    prompt=${prompt}
    ...    prompt_timeout=${prompt_timeout}
    # ${output} contains the system prompt and all we want is the value of the number
    ${thread_count}=    Fetch From Left    ${output}    \r
    [Return]    ${thread_count}

Strip Quotes
    [Arguments]    ${string_to_strip}
    [Documentation]    Will strip ALL quotes from given string and return the new string
    ${string_to_return}=    Replace String    ${string_to_strip}    "    \    count=-1
    [Return]    ${string_to_return}


Run Command On Remote System
    [Arguments]    ${system}    ${cmd}    ${user}=${DEFAULT_USER}    ${password}=${EMPTY}    ${prompt}=${DEFAULT_LINUX_PROMPT}    ${prompt_timeout}=${DEFAULT_TIMEOUT}
    [Documentation]    Reduces the common work of running a command on a remote system to a single higher level
    ...    robot keyword, taking care to log in with a public key and. The command given is written
    ...    and the output returned. No test conditions are checked.
    ${current_ssh_connection}=    SSHLibrary.Get Connection
    BuiltIn.Log    Attempting to execute command "${cmd}" on remote system "${system}" by user "${user}" with keyfile pass "${keyfile_pass}" and prompt "${prompt}"
    BuiltIn.Log    ${password}
    ${conn_id}=    SSHLibrary.Open Connection    ${system}    prompt=${prompt}    timeout=${prompt_timeout}
    SSHKeywords.Flexible SSH Login    ${user}    ${password}
    ${stdout}    ${stderr}    SSHLibrary.Execute Command    ${cmd}    return_stderr=True
    SSHLibrary.Close Connection
    Log    ${stderr}
    [Teardown]    CommonSSHKeywords.Restore_Current_SSH_Connection_From_Index    ${current_ssh_connection.index}
    [Return]    ${stdout}



Run Command On Mininet
    [Arguments]    ${system}=${TOOLS_SYSTEM_IP}    ${cmd}=echo    ${user}=${TOOLS_SYSTEM_USER}    ${password}=${TOOLS_SYSTEM_PASSWORD}    ${prompt}=${TOOLS_SYSTEM_PROMPT}
    [Documentation]    Call Run Comand On Remote System, but with default values suitable for Mininet machine.
    BuiltIn.Run Keyword And Return    Run Command On Remote System    ${system}    ${cmd}    ${user}    ${password}    prompt=${prompt}

Run Command On Controller
    [Arguments]    ${system}=${ODL_SYSTEM_IP}    ${cmd}=echo    ${user}=${ODL_SYSTEM_USER}    ${password}=${ODL_SYSTEM_PASSWORD}    ${prompt}=${ODL_SYSTEM_PROMPT}
    [Documentation]    Call Run Comand On Remote System, but with default values suitable for Controller machine.
    BuiltIn.Log    ${password}
    BuiltIn.Run Keyword And Return    Run Command On Remote System    ${system}    ${cmd}    ${user}    ${password}    prompt=${prompt}


Verify File Exists On Remote System
    [Arguments]    ${system}    ${file}    ${user}=${TOOLS_SYSTEM_USER}    ${password}=${TOOLS_SYSTEM_PASSWORD}    ${prompt}=${DEFAULT_LINUX_PROMPT}    ${prompt_timeout}=5s
    [Documentation]    Will create connection with public key and will PASS if the given ${file} exists,
    ...    otherwise will FAIL
    ${conn_id}=    Open Connection    ${system}    prompt=${prompt}    timeout=${prompt_timeout}
    SSHKeywords.Flexible SSH Login    ${user}    ${password}
    SSHLibrary.File Should Exist    ${file}
    Close Connection

Get Epoch Time
    [Arguments]    ${time}
    [Documentation]    Get the Epoc time from MM/DD/YYYY HH:MM:SS
    ${epoch_time}=    Convert Date    ${time}    epoch    exclude_milles=True    date_format=%m/%d/%Y %H:%M:%S
    ${epoch_time}=    Convert To Integer    ${epoch_time}
    [Return]    ${epoch_time}


Remove Space on String
    [Arguments]    ${str}    ${count}=-1
    [Documentation]    Remove the empty space from given string.count is optional,if its given
    ...    that many occurence of space will be removed from left
    ${x}=    Convert To String    ${str}
    ${x}=    Replace String    ${str}    ${SPACE}    ${EMPTY}    count=${count}
    [Return]    ${x}

Split Value from String
    [Arguments]    ${str}    ${splitter}
    [Documentation]    Split the String based on given splitter and return as list
    @{x}=    Split String    ${str}    ${splitter}
    [Return]    @{x}

Concatenate the String
    [Arguments]    ${str1}    ${str2}
    [Documentation]    Catenate the two non-string objects and return as String
    ${str1}=    Convert to String    ${str1}
    ${str2}=    Convert to String    ${str2}
    ${output}=    Catenate    ${str1}    ${str2}
    [Return]    ${output}

Post Elements To URI
    [Arguments]    ${rest_uri}    ${data}    ${headers}=${headers}    ${session}=session
    [Documentation]    Perform a POST rest operation, using the URL and data provided
    ${resp} =    RequestsLibrary.Post Request    ${session}    ${rest_uri}    data=${data}    headers=${headers}
    Log    ${resp.content}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}

Remove All Elements At URI
    [Arguments]    ${uri}    ${session}=session
    ${resp}    RequestsLibrary.Delete Request    ${session}    ${uri}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}

Remove All Elements At URI And Verify
    [Arguments]    ${uri}    ${session}=session
    ${resp}    RequestsLibrary.Delete Request    ${session}    ${uri}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}
    ${resp}    RequestsLibrary.Get Request    ${session}    ${uri}
    Should Be Equal As Strings    ${resp.status_code}    404

Remove All Elements If Exist
    [Arguments]    ${uri}    ${session}=session
    [Documentation]    Delete all elements from an URI if the configuration was not empty
    ${resp}    RequestsLibrary.Get Request    ${session}    ${uri}
    Run Keyword If    '${resp.status_code}'!='404'    Remove All Elements At URI    ${uri}    ${session}

Add Elements To URI From File
    [Arguments]    ${dest_uri}    ${data_file}    ${headers}=${headers}    ${session}=session
    ${body}    OperatingSystem.Get File    ${data_file}
    ${resp}    RequestsLibrary.Put Request    ${session}    ${dest_uri}    data=${body}    headers=${headers}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}

Add Elements To URI From File And Verify
    [Arguments]    ${dest_uri}    ${data_file}    ${headers}=${headers}    ${session}=session
    ${body}    OperatingSystem.Get File    ${data_file}
    ${resp}    RequestsLibrary.Put Request    ${session}    ${dest_uri}    data=${body}    headers=${headers}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}
    ${resp}    RequestsLibrary.Get Request    ${session}    ${dest_uri}
    Should Not Be Equal    ${resp.status_code}    404

Add Elements To URI And Verify
    [Arguments]    ${dest_uri}    ${data_file}    ${headers}=${headers}    ${session}=session
    ${resp}    RequestsLibrary.Put Request    ${session}    ${dest_uri}    ${data_file}    headers=${headers}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}
    ${resp}    RequestsLibrary.Get Request    ${session}    ${dest_uri}
    Should Not Be Equal    ${resp.status_code}    404

Add Elements To URI From File And Check Validation Error
    [Arguments]    ${dest_uri}    ${data_file}    ${headers}=${headers}    ${session}=session
    [Documentation]    Shorthand for PUTting data from file and expecting status code 400.
    BuiltIn.Comment    TODO: Does this have any benefits, considering TemplatedRequests can also do this in one line?
    ${body}    OperatingSystem.Get File    ${data_file}
    ${resp}    RequestsLibrary.Put Request    ${session}    ${dest_uri}    data=${body}    headers=${headers}
    Should Contain    ${DATA_VALIDATION_ERROR}    ${resp.status_code}

Add Elements To URI From File And Check Server Error
    [Arguments]    ${dest_uri}    ${data_file}    ${headers}=${headers}    ${session}=session
    [Documentation]    Shorthand for PUTting data from file and expecting status code 500.
    ...    Consider opening a Bug against ODL, as in most test cases, 400 is the http code to expect.
    BuiltIn.Comment    TODO: Does this have any benefits, considering TemplatedRequests can also do this in one line?
    ${body}    OperatingSystem.Get File    ${data_file}
    ${resp}    RequestsLibrary.Put Request    ${session}    ${dest_uri}    data=${body}    headers=${headers}
    Should Contain    ${INTERNAL_SERVER_ERROR}    ${resp.status_code}

Post Elements To URI From File
    [Arguments]    ${dest_uri}    ${data_file}    ${headers}=${headers}    ${session}=session
    ${body}    OperatingSystem.Get File    ${data_file}
    ${resp}    RequestsLibrary.Post Request    ${session}    ${dest_uri}    data=${body}    headers=${headers}
    Should Contain    ${ALLOWED_STATUS_CODES}    ${resp.status_code}

Run Process With Logging And Status Check
    [Arguments]    @{proc_args}
    [Documentation]    Execute an OS command, log STDOUT and STDERR output and check exit code to be 0
    ${result}=    Run Process    @{proc_args}
    Log    ${result.stdout}
    Log    ${result.stderr}
    Should Be Equal As Integers    ${result.rc}    0
    [Return]    ${result}

Get Data From URI
    [Arguments]    ${session}    ${uri}    ${headers}=${NONE}
    [Documentation]    Issue a GET request and return the data obtained or on error log the error and fail.
    ...    Issues a GET request for ${uri} in ${session} using headers from
    ...    ${headers}. If the request returns a HTTP error, fails. Otherwise
    ...    returns the data obtained by the request.
    ${response}=    RequestsLibrary.Get Request    ${session}    ${uri}    ${headers}
    Builtin.Return_From_Keyword_If    ${response.status_code} == 200    ${response.text}
    Builtin.Log    ${response.text}
    Builtin.Fail    The request failed with code ${response.status_code}

No Content From URI
    [Arguments]    ${session}    ${uri}    ${headers}=${NONE}
    [Documentation]    Issue a GET request and return on error 404 (No content) or will fail and log the content.
    ...    Issues a GET request for ${uri} in ${session} using headers from
    ...    ${headers}. If the request returns a HTTP error, fails. Otherwise
    ...    returns the data obtained by the request.
    ${response}=    RequestsLibrary.Get Request    ${session}    ${uri}    ${headers}
    Builtin.Return_From_Keyword_If    ${response.status_code} == 404
    Builtin.Log    ${response.text}
    Builtin.Fail    The request failed with code ${response.status_code}

Get Index From List Of Dictionaries
    [Arguments]    ${dictionary_list}    ${key}    ${value}
    [Documentation]    Extract index for the dictionary in a list that contains a key-value pair. Returns -1 if key-value is not found.
    ${length}=    Get Length    ${dictionary_list}
    ${index}=    Set Variable    -1
    : FOR    ${i}    IN RANGE    ${length}
    \    ${dictionary}=    Get From List    ${dictionary_list}    ${i}
    \    Run Keyword If    """&{dictionary}[${key}]""" == """${value}"""    Set Test Variable    ${index}    ${i}
    [Return]    ${index}

Check Item Occurrence
    [Arguments]    ${string}    ${dictionary_item_occurrence}
    [Documentation]    Check string for occurrences of items expressed in a list of dictionaries {item=occurrences}. 0 occurences means item is not present.
    : FOR    ${item}    IN    @{dictionary_item_occurrence}
    \    Should Contain X Times    ${string}    ${item}    &{dictionary_item_occurrence}[${item}]

Post Log Check
    [Arguments]    ${uri}    ${body}    ${status_code}=200    ${session}=session
    [Documentation]    Post body to ${uri}, log response content, and check status
    ${resp}=    RequestsLibrary.Post Request    ${session}    ${uri}    ${body}
    Log    ${resp.content}
    Should Be Equal As Strings    ${resp.status_code}    ${status_code}
    [Return]    ${resp}

Get Log File Name
    [Arguments]    ${testtool}    ${testcase}=${EMPTY}
    [Documentation]    Get the name of the suite sanitized to be usable as a part of filename.
    ...    These names are used to constructs names of the log files produced
    ...    by the testing tools so two suites using a tool wont overwrite the
    ...    log files if they happen to run in one job.
    ${name}=    BuiltIn.Evaluate    """${SUITE_NAME}""".replace(" ","-").replace("/","-").replace(".","-")
    ${suffix}=    BuiltIn.Set_Variable_If    '${testcase}' != ''    --${testcase}    ${EMPTY}
    [Return]    ${testtool}--${name}${suffix}.log

Set_User_Configurable_Variable_Default
    [Arguments]    ${name}    ${value}
    [Documentation]    Set a default value for an user configurable variable.
    ...    This keyword is needed if your default value is calculated using
    ...    a complex expression which needs BuiltIn.Evaluate or even more
    ...    complex keywords. It sets the variable ${name} (the name of the
    ...    variable MUST be specified WITHOUT the ${} syntactic sugar due
    ...    to limitations of Robot Framework) to ${value} but only if the
    ...    variable ${name} was not set previously. This keyword is intended
    ...    for user configurable variables which are supposed to be set only
    ...    with pybot -v; calling this keyword on a variable that was already
    ...    set by another keyword will silently turn the call into a NOP and
    ...    thus is a bug in the suite or resource trying to call this
    ...    keyword.
    # TODO: Figure out how to make the ${value} evaluation "lazy" (meaning
    #    evaluating it only when the user did not set anything and thus the
    #    default is needed). This might be needed to avoid potentially costly
    #    keyword invocations when they are not needed. Currently no need for
    #    this was identified, thus leaving it here as a TODO. Based on
    #    comments the best approach would be to create another keyword that
    #    expects a ScalarClosure in the place of ${value} and calls the
    #    closure to get the value but only if the value is needed).
    #    The best idea how to implement this "laziness" would be to have the
    #    used to define another keyword that will be responsible for getting
    #    the default value and then passing the name of this getter keyword
    #    to this keyword. Then this keyword would call the getter (to obtain
    #    the expensive default value) only if it discovers that this value
    #    is really needed (because the variable is not set yet).
    # TODO: Is the above TODO really necessary? Right now we don't have any
    #    examples of "expensive default values" where to obtain the default
    #    value is so expensive on resources (e.g. need to SSH somewhere to
    #    check something) that we would want to skip the calculation if the
    #    variable for which it is needed has a value already provided by the
    #    user using "pybot -v" or something. One example would be
    #    JAVA_HOME if it would be designed as user-configurable variable
    #    (currently it is not; users can specify "use jdk7" or "use jdk8"
    #    but not "use the jdk over there"; and there actually is no JAVA_HOME
    #    present in the resource, rather the Java invocation command uses the
    #    Java invocation with a full path). The default value of JAVA_HOME
    #    has to be obtained by issuing commands on the SSH connection where
    #    the resulting Java invocation command will be used (to check
    #    multiple candidate paths until one that fits is found) and we could
    #    skip all this checking if a JAVA_HOME was supplied by the user using
    #    "pybot -v".
    ${value}=    BuiltIn.Get_Variable_Value    \${${name}}    ${value}
    BuiltIn.Set_Suite_Variable    \${${name}}    ${value}

Convert_To_Minutes
    [Arguments]    ${time}
    [Documentation]    Convert a Robot time string to an integer expressing the time in minutes, rounded up
    ...    This is a wrapper around DateTime.Convert_Time which does not
    ...    provide this functionality directly nor is even able to produce
    ...    an integer directly. It is needed for RestPerfClient which
    ...    cannot accept floats for its --timeout parameter and interprets
    ...    the value supplied in this parameter in minutes.
    ${seconds}=    DateTime.Convert_Time    ${time}    result_format=number
    ${minutes}=    BuiltIn.Evaluate    int(math.ceil(${seconds}/60.0))    modules=math
    [Return]    ${minutes}

Write Commands Until Expected Prompt
    [Arguments]    ${cmd}    ${prompt}    ${timeout}=30s
    [Documentation]    quick wrapper for Write and Read Until Prompt Keywords to make test cases more readable
    SSHLibrary.Set Client Configuration    timeout=${timeout}
    SSHLibrary.Read
    SSHLibrary.Write    ${cmd}
    ${output}=    SSHLibrary.Read Until    ${prompt}
    [Return]    ${output}

Install Package On Ubuntu System
    [Arguments]    ${package_name}    ${system}=${TOOLS_SYSTEM_IP}    ${user}=${TOOLS_SYSTEM_USER}    ${password}=${TOOLS_SYSTEM_PASSWORD}    ${prompt}=${DEFAULT_LINUX_PROMPT}    ${prompt_timeout}=30s
    [Documentation]    Keyword to install packages for testing to Ubuntu Mininet VM
    Log    Keyword to install package to Mininet Ubuntu VM
    Open Connection    ${system}    prompt=${prompt}    timeout=${prompt_timeout}
    SSHKeywords.Flexible Mininet Login    user=${user}    password=${password}
    Write    sudo apt-get install -y ${package_name}
    Read Until    ${prompt}

Json Parse From String
    [Arguments]    ${plain_string_with_json}
    [Documentation]    Parse given plain string into json (dictionary)
    ${json_data}    Evaluate    json.loads('''${plain_string_with_json}''')    json
    [Return]    ${json_data}

Json Parse From File
    [Arguments]    ${json_file}
    [Documentation]    Parse given file content into json (dictionary)
    ${json_plain_string}    Get file    ${json_file}
    ${json_data}    Json Parse From String    ${json_plain_string}
    [Return]    ${json_data}
