*** Settings ***
Documentation   This suite tests Platform Event Log (PEL) functionality of OpenBMC.

Library         ../../lib/pel_utils.py
Variables       ../../data/pel_variables.py
Resource        ../../lib/openbmc_ffdc.robot

Test Setup      Redfish.Login
Test Teardown   Run Keywords  Redfish.Logout  AND  FFDC On Test Case Fail


*** Variables ***

${CMD_INTERNAL_FAILURE}  busctl call xyz.openbmc_project.Logging /xyz/openbmc_project/logging
...  xyz.openbmc_project.Logging.Create Create ssa{ss} xyz.openbmc_project.Common.Error.InternalFailure
...  xyz.openbmc_project.Logging.Entry.Level.Error 0


*** Test Cases ***

Create Test PEL Log And Verify
    [Documentation]  Create PEL log using busctl command and verify via peltool.
    [Tags]  Create_Test_PEL_Log_And_Verify

    Redfish Purge Event Log
    Create Test PEL Log
    ${pel_id}=  Get PEL Log Via BMC CLI
    Should Not Be Empty  ${pel_id}  msg=System PEL log entry is empty.


Verify PEL Log Details
    [Documentation]  Verify PEL log details via peltool.
    [Tags]  Verify_PEL_Log_Details

    Redfish Purge Event Log

    ${bmc_time1}=  CLI Get BMC DateTime
    Create Test PEL Log
    ${bmc_time2}=  CLI Get BMC DateTime

    ${pel_records}=  Peltool  -l

    # Example output from 'Peltool  -l':
    # pel_records:
    # [0x50000012]:
    #   [CreatorID]:                  BMC
    #   [CompID]:                     0x1000
    #   [PLID]:                       0x50000012
    #   [Subsystem]:                  BMC Firmware
    #   [Message]:                    An application had an internal failure
    #   [SRC]:                        BD8D1002
    #   [Commit Time]:                03/02/2020  09:35:15
    #   [Sev]:                        Unrecoverable Error

    ${ids}=  Get Dictionary Keys  ${pel_records}
    ${id}=  Get From List  ${ids}  0

    @{pel_fields}=  Create List  CreatorID  Subsystem  Message  Sev
    FOR  ${field}  IN  @{pel_fields}
      Valid Value  pel_records['${id}']['${field}']  ['${PEL_DETAILS['${field}']}']
    END

    Valid Value  pel_records['${id}']['PLID']  ['${id}']

    # Verify if "CompID" and "SRC" fields of PEL has alphanumeric value.
    Should Match Regexp  ${pel_records['${id}']['CompID']}  [a-zA-Z0-9]
    Should Match Regexp  ${pel_records['${id}']['SRC']}  [a-zA-Z0-9]

    ${pel_date_time}=  Convert Date  ${pel_records['${id}']['Commit Time']}
    ...  date_format=%m/%d/%Y %H:%M:%S  exclude_millis=yes

    # Convert BMC and PEL time to epoch time before comparing.
    ${bmc_time1_epoch}=  Convert Date  ${bmc_time1}  epoch
    ${pel_time_epoch}=  Convert Date  ${pel_date_time}  epoch
    ${bmc_time2_epoch}=  Convert Date  ${bmc_time2}  epoch

    Should Be True  ${bmc_time1_epoch} <= ${pel_time_epoch} <= ${bmc_time2_epoch}


Verify PEL Log Persistence After BMC Reboot
    [Documentation]  Verify PEL log persistence after BMC reboot.
    [Tags]  Verify_PEL_Log_Persistence_After_BMC_Reboot

    Create Test PEL Log
    ${pel_before_reboot}=  Get PEL Log Via BMC CLI

    Redfish OBMC Reboot (off)
    ${pel_after_reboot}=  Get PEL Log Via BMC CLI

    List Should Contain Sub List  ${pel_after_reboot}  ${pel_before_reboot}


Verify PEL ID Numbering
    [Documentation]  Verify PEL ID numbering.
    [Tags]  Verify_PEL_ID_Numbering

    Redfish Purge Event Log
    Create Test PEL Log
    Create Test PEL Log

    ${pel_ids}=  Get PEL Log Via BMC CLI

    # Example of PEL IDs from PEL logs.
    #  [0x50000012]:             <--- First PEL ID
    #    [CreatorID]:                  BMC
    #    [CompID]:                     0x1000
    #    [PLID]:                       0x50000012
    #    [Subsystem]:                  BMC Firmware
    #    [Message]:                    An application had an internal failure
    #    [SRC]:                        BD8D1002
    #    [Commit Time]:                03/02/2020  09:35:15
    #    [Sev]:                        Unrecoverable Error
    #
    #  [0x50000013]:             <--- Second PEL ID
    #    [CreatorID]:                  BMC
    #    [CompID]:                     0x1000
    #    [PLID]:                       0x50000013
    #    [Subsystem]:                  BMC Firmware
    #    [Message]:                    An application had an internal failure
    #    [SRC]:                        BD8D1002
    #    [Commit Time]:                03/02/2020  09:35:15
    #    [Sev]:                        Unrecoverable Error

    Should Be True  ${pel_ids[1]} == ${pel_ids[0]}+1


Verify Host Off State From PEL
    [Documentation]  Verify Host off state from PEL.
    [Tags]  Verify_Host_Off_State_From_PEL

    Redfish Power Off  stack_mode=skip
    Create Test PEL Log

    ${pel_ids}=  Get PEL Log Via BMC CLI
    ${id}=  Get From List  ${pel_ids}  -1
    ${pel_host_state}=  Get PEL Field Value  ${id}  User Data  HostState

    Valid Value  pel_host_state  ['Off']


Verify BMC Version From PEL
    [Documentation]  Verify BMC Version from PEL.
    [Tags]  Verify_BMC_Version_From_PEL

    Create Test PEL Log

    ${pel_ids}=  Get PEL Log Via BMC CLI
    ${id}=  Get From List  ${pel_ids}  -1
    ${pel_bmc_version}=  Get PEL Field Value  ${id}  User Data  BMC Version ID

    ${bmc_version}=  Get BMC Version
    Valid Value  bmc_version  ['${bmc_version}']


*** Keywords ***

Create Test PEL Log
    [Documentation]  Generate test PEL log.

    # Test PEL log entry example:
    # {
    #    "0x5000002D": {
    #            "SRC": "BD8D1002",
    #            "Message": "An application had an internal failure",
    #            "PLID": "0x5000002D",
    #            "CreatorID": "BMC",
    #            "Subsystem": "BMC Firmware",
    #            "Commit Time": "02/25/2020  04:47:09",
    #            "Sev": "Unrecoverable Error",
    #            "CompID": "0x1000"
    #    }
    # }

    BMC Execute Command  ${CMD_INTERNAL_FAILURE}


Get PEL Log Via BMC CLI
    [Documentation]  Returns the list of PEL IDs using BMC CLI.

    ${pel_records}=  Peltool  -l
    ${ids}=  Get Dictionary Keys  ${pel_records}
    Sort List  ${ids}

    [Return]  ${ids}


Get PEL Field Value
    [Documentation]  Returns the value of given PEL's field.
    [Arguments]  ${pel_id}  ${pel_section}  ${pel_field}

    # Description of argument(s):
    # pel_id           The ID of PEL (e.g. 0x5000002D, 0x5000002E).
    # pel_section      The section of PEL (e.g. Private Header, User Header)
    # pel_field        The PEL field (e.g. Event Severity, Event Type).

    ${pel_output}=  Peltool  -i ${pel_id}

    # Example of PEL output from "peltool -i <id>" command.
    #  [Private Header]:
    #    [Created at]:                                 08/24/1928 12:04:06
    #    [Created by]:                                 0x584D
    #    [Sub-section type]:                           0
    #    [Entry Id]:                                   0x50000BB7
    #    [Platform Log Id]:                            0x8200061D
    #    [CSSVER]:
    #    [Section Version]:                            1
    #    [Creator Subsystem]:                          PHYP
    #    [BMC Event Log Id]:                           341
    #    [Committed at]:                               03/25/1920 12:06:22
    #  [User Header]:
    #    [Log Committed by]:                           0x4552
    #    [Action Flags]:
    #      [0]:                                        Report Externally
    #    [Subsystem]:                                  I/O Subsystem
    #    [Event Type]:                                 Miscellaneous, Informational Only
    #    [Sub-section type]:                           0
    #    [Event Scope]:                                Entire Platform
    #    [Event Severity]:                             Informational Event
    #    [Host Transmission]:                          Not Sent
    #    [Section Version]:                            1

    ${pel_section_output}=  Get From Dictionary  ${pel_output}  ${pel_section}
    ${pel_field_output}=  Get From Dictionary  ${pel_section_output}  ${pel_field}

    [Return]  ${pel_field_output}

