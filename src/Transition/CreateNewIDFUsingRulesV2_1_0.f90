MODULE SetVersion

USE DataStringGlobals
USE DataVCompareGlobals

PUBLIC

CONTAINS

SUBROUTINE SetThisVersionVariables()
      VerString='Conversion 2.0 => 2.1'
      VersionNum=2.0
      IDDFileNameWithPath=TRIM(ProgramPath)//'V2-0-0-Energy+.idd'
      NewIDDFileNameWithPath=TRIM(ProgramPath)//'V2-1-0-Energy+.idd'
      RepVarFileNameWithPath=TRIM(ProgramPath)//'Report Variables 2-0-0-025 to 2-1-0.csv'
END SUBROUTINE

END MODULE

SUBROUTINE CreateNewIDFUsingRules(EndOfFile,DiffOnly,InLfn,AskForInput,InputFileName,ArgFile,ArgIDFExtension)

          ! SUBROUTINE INFORMATION:
          !       AUTHOR         Linda Lawrie
          !       DATE WRITTEN   July 2002
          !       MODIFIED       For each release
          !       RE-ENGINEERED  na

          ! PURPOSE OF THIS SUBROUTINE:
          ! This subroutine creates new IDFs based on the rules specified by
          ! developers.  This will result in a more complete transition but
          ! takes more time to create.   This routine is specifically for rules
          ! 2.0.0 to 2.1.0.

          ! METHODOLOGY EMPLOYED:
          ! na

          ! REFERENCES:
          ! na

          ! USE STATEMENTS:
  USE InputProcessor
  USE DataVCompareGlobals
  USE VCompareGlobalRoutines
  USE General
  USE DataGlobals, ONLY: ShowMessage, ShowContinueError, ShowFatalError, ShowSevereError, ShowWarningError

  IMPLICIT NONE    ! Enforce explicit typing of all variables in this routine

          ! SUBROUTINE ARGUMENT DEFINITIONS:
  LOGICAL, INTENT(INOUT) :: EndOfFile
  LOGICAL, INTENT(IN)    :: DiffOnly
  INTEGER, INTENT(IN)    :: InLfn
  LOGICAL, INTENT(IN)    :: AskForInput
  CHARACTER(len=*), INTENT(IN) :: InputFileName
  LOGICAL, INTENT(IN)    :: ArgFile
  CHARACTER(len=*), INTENT(IN) :: ArgIDFExtension

          ! SUBROUTINE PARAMETER DEFINITIONS:
  CHARACTER(len=*), PARAMETER :: fmta="(A)"

          ! INTERFACE BLOCK SPECIFICATIONS
          ! na

          ! DERIVED TYPE DEFINITIONS
          ! na

          ! SUBROUTINE LOCAL VARIABLE DECLARATIONS:
  INTEGER IoS
  INTEGER DotPos
  INTEGER NA
  INTEGER NN
  INTEGER CurArgs
  INTEGER DifLfn
  INTEGER xCount
  INTEGER Num
  INTEGER, EXTERNAL :: GetNewUnitNumber
  INTEGER, EXTERNAL :: FindNumber
  INTEGER Arg
  CHARACTER(len=30) UnitsArg
  CHARACTER(len=MaxNameLength) ObjectName
  CHARACTER(len=30), EXTERNAL :: TrimTrailZeros
  CHARACTER(len=MaxNameLength) UCRepVarName
  CHARACTER(len=MaxNameLength) UCCompRepVarName
  LOGICAL DelThis
  INTEGER pos
  LOGICAL ExitBecauseBadFile
  LOGICAL StillWorking
  LOGICAL NoDiff
  LOGICAL checkrvi
  LOGICAL NoVersion
  LOGICAL DiffMinFields  ! Set to true when diff number of min-fields between the two objects
  LOGICAL Written
  INTEGER :: Var
  INTEGER :: CurVar
  LOGICAL ArgFileBeingDone
  LOGICAL LatestVersion
  CHARACTER(len=10) :: LocalFileExtension=' '
  LOGICAL :: WildMatch
  LOGICAL :: COMISSim
  LOGICAL :: ADSSim
  LOGICAL :: FileExist
  CHARACTER(len=MaxNameLength) :: CreatedOutputName
  LOGICAL, ALLOCATABLE, DIMENSION(:) :: DeleteThisRecord

  REAL SaveNumber
  LOGICAL :: ErrFlag

  StillWorking=.true.
  ArgFileBeingDone=.false.
  LatestVersion=.false.
  LocalFileExtension=ArgIDFExtension
  EndOfFile=.false.
  IOS=0

  DO WHILE (StillWorking)

    ExitBecauseBadFile=.false.
    DO WHILE (.not. EndOfFile)
      IF (AskForInput) THEN
        WRITE(*,*) 'Enter input file name, with path'
        write(*,fmta,advance='no') '-->'
        READ(*,fmta) FullFileName
      ELSE
        IF (.not. ArgFile) THEN
          READ(InLfn,*,IOSTAT=IoS) FullFileName
        ELSEIF (.not. ArgFileBeingDone) THEN
          FullFileName=InputFileName
          IOS=0
          ArgFileBeingDone=.true.
        ELSE
          FullFileName=Blank
          IOS=1
        ENDIF
        IF (FullFileName(1:1) == '!') THEN
          FullFileName=Blank
          CYCLE
        ENDIF
      ENDIF
      UnitsArg=Blank
      IF (IoS /= 0) FullFileName=Blank
      FullFileName=ADJUSTL(FullFileName)
      IF (FullFileName /= Blank) THEN
        CALL DisplayString('Processing IDF -- '//TRIM(FullFileName))
        WRITE(Auditf,fmta) ' Processing IDF -- '//TRIM(FullFileName)
        DotPos=SCAN(FullFileName,'.',.true.) ! Scan backward looking for extension,
        IF (DotPos /= 0) THEN
          FileNamePath=FullFileName(1:DotPos-1)
          LocalFileExtension=MakeLowerCase(FullFileName(DotPos+1:))
        ELSE
          FileNamePath=FullFileName
          WRITE(*,*) ' assuming file extension of .idf'
          WRITE(Auditf,fmta) ' ..assuming file extension of .idf'
          FullFileName=TRIM(FullFileName)//'.idf'
          LocalFileExtension='idf'
        ENDIF
        ! Process the old input
        DifLfn=GetNewUnitNumber()
        INQUIRE(File=TRIM(FullFileName),EXIST=FileOK)
        IF (.not. FileOK) THEN
          WRITE(*,*) 'File not found='//TRIM(FullFileName)
          WRITE(Auditf,*) 'File not found='//TRIM(FullFileName)
          EndOfFile=.true.
          ExitBecauseBadFile=.true.
          EXIT
        ENDIF
        IF (LocalFileExtension == 'idf' .or. LocalFileExtension == 'imf') THEN
          checkrvi=.false.
          COMISSim=.false.
          ADSSim=.false.
          IF (DiffOnly) THEN
            OPEN(DifLfn,FILE=TRIM(FileNamePath)//'.'//TRIM(LocalFileExtension)//'dif')
          ELSE
            OPEN(DifLfn,FILE=TRIM(FileNamePath)//'.'//TRIM(LocalFileExtension)//'new')
          ENDIF
          IF (LocalFileExtension == 'imf') THEN
            CALL ShowWarningError('Note: IMF file being processed.  No guarantee of perfection.  Please check new file carefully.',Auditf)
            ProcessingIMFFile=.true.
          ELSE
            ProcessingIMFFile=.false.
          ENDIF
          CALL ProcessInput(IDDFileNameWithPath,NewIDDFileNameWithPath,FullFileName)
          IF (FatalError) THEN
            ExitBecauseBadFile=.true.
            EXIT
          ENDIF

          ALLOCATE(Alphas(MaxAlphaArgsFound),Numbers(MaxNumericArgsFound))
          ALLOCATE(InArgs(MaxTotalArgs))
          ALLOCATE(AorN(MaxTotalArgs),ReqFld(MaxTotalArgs),FldNames(MaxTotalArgs),FldDefaults(MaxTotalArgs),FldUnits(MaxTotalArgs))
          ALLOCATE(NwAorN(MaxTotalArgs),NwReqFld(MaxTotalArgs),NwFldNames(MaxTotalArgs),NwFldDefaults(MaxTotalArgs),NwFldUnits(MaxTotalArgs))
          ALLOCATE(OutArgs(MaxTotalArgs))
          ALLOCATE(MatchArg(MaxTotalArgs))
          ALLOCATE(DeleteThisRecord(NumIDFRecords))
          DeleteThisRecord=.false.

          DO Num=1,NumIDFRecords
            IF (MakeUPPERCase(IDFRecords(Num)%Name) == 'COMIS SIMULATION') COMISSim=.true.
            IF (MakeUPPERCase(IDFRecords(Num)%Name) == 'ADS SIMULATION') ADSSim=.true.
          ENDDO
          IF (COMISSim .and. ADSSim) THEN
            WRITE(*,*) 'File contains both COMIS and ADS Simulation objects='//TRIM(FullFileName)
            WRITE(*,*) 'Please contact EnergyPlus Support (energyplus-support@gard.com) for help in transitioning this file.'
            WRITE(Auditf,fmta) ' ..File contains both COMIS and ADS Simulation objects='//TRIM(FullFileName)
            WRITE(Auditf,fmta) ' ..Please contact EnergyPlus Support (energyplus-support@gard.com) for help in transitioning this file.'
            ExitBecauseBadFile=.true.
            EXIT
          ENDIF

          NoVersion=.true.
          DO Num=1,NumIDFRecords
            IF (MakeUPPERCase(IDFRecords(Num)%Name) /= 'VERSION') CYCLE
            NoVersion=.false.
            EXIT
          ENDDO

          DO Num=1,NumIDFRecords

            DO xcount=IDFRecords(Num)%CommtS+1,IDFRecords(Num)%CommtE
              WRITE(DifLfn,fmta) TRIM(Comments(xcount))
              if (xcount == IDFRecords(Num)%CommtE) WRITE(DifLfn,fmta) ' '
            ENDDO
            IF (NoVersion .and. Num == 1) THEN
              CALL GetNewObjectDefInIDD('VERSION',NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
              OutArgs(1)='2.1'
              CurArgs=1
              CALL WriteOutIDFLinesAsComments(DifLfn,'VERSION',CurArgs,OutArgs,NwFldNames,NwFldUnits)
            ENDIF

     ! deleted objects.  no transition.
            IF (MakeUPPERCase(TRIM(IDFRecords(Num)%Name)) == 'SKY RADIANCE DISTRIBUTION') CYCLE
            IF (MakeUPPERCase(TRIM(IDFRecords(Num)%Name)) == 'AIRFLOW MODEL') CYCLE
            IF (MakeUPPERCase(TRIM(IDFRecords(Num)%Name)) == 'GENERATOR:FC:BATTERY DATA') CYCLE
            IF (MakeUPPERCase(TRIM(IDFRecords(Num)%Name)) == 'WATER HEATER:SIMPLE') THEN
              WRITE(DifLfn,fmta) ! The WATER HEATER:SIMPLE object has been deleted'
              CYCLE
            ENDIF

            ObjectName=IDFRecords(Num)%Name
            IF (FindItemInList(ObjectName,ObjectDef%Name,NumObjectDefs) /= 0) THEN
              CALL GetObjectDefInIDD(ObjectName,NumArgs,AorN,ReqFld,ObjMinFlds,FldNames,FldDefaults,FldUnits)
              NumAlphas=IDFRecords(Num)%NumAlphas
              NumNumbers=IDFRecords(Num)%NumNumbers
              Alphas(1:NumAlphas)=IDFRecords(Num)%Alphas(1:NumAlphas)
              Numbers(1:NumNumbers)=IDFRecords(Num)%Numbers(1:NumNumbers)
              CurArgs=NumAlphas+NumNumbers
              InArgs=Blank
              OutArgs=Blank
              NA=0
              NN=0
              DO Arg=1,CurArgs
                IF (AorN(Arg)) THEN
                  NA=NA+1
                  InArgs(Arg)=Alphas(NA)
                ELSE
                  NN=NN+1
                  InArgs(Arg)=Numbers(NN)
                ENDIF
              ENDDO
            ELSE
              WRITE(Auditf,fmta) 'Object="'//TRIM(ObjectName)//'" does not seem to be on the "old" IDD.'
              WRITE(Auditf,fmta) '... will be listed as comments (no field names) on the new output file.'
              WRITE(Auditf,fmta) '... Alpha fields will be listed first, then numerics.'
              NumAlphas=IDFRecords(Num)%NumAlphas
              NumNumbers=IDFRecords(Num)%NumNumbers
              Alphas(1:NumAlphas)=IDFRecords(Num)%Alphas(1:NumAlphas)
              Numbers(1:NumNumbers)=IDFRecords(Num)%Numbers(1:NumNumbers)
              DO Arg=1,NumAlphas
                OutArgs(Arg)=Alphas(Arg)
              ENDDO
              NN=NumAlphas+1
              DO Arg=1,NumNumbers
                OutArgs(NN)=Numbers(Arg)
                NN=NN+1
              ENDDO
              CurArgs=NumAlphas+NumNumbers
              NwFldNames=Blank
              NwFldUnits=Blank
              CALL WriteOutIDFLinesAsComments(DifLfn,ObjectName,CurArgs,OutArgs,NwFldNames,NwFldUnits)
              CYCLE
            ENDIF

            Nodiff=.true.       ! Nodiff is true by default
            DiffMinFields=.false.
            Written=.false.

            IF (FindItemInList(MakeUPPERCase(ObjectName),NotInNew,SIZE(NotInNew)) == 0) THEN
              CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
              ! Check minfields
              IF (ObjMinFlds /= NwObjMinFlds) THEN
                DiffMinFields=.true.
              ELSE
                DiffMinFields=.false.
              ENDIF
            ENDIF

            IF (.not. MakingPretty) THEN

              SELECT CASE (MakeUPPERCase(TRIM(IDFRecords(Num)%Name)))

              CASE ('VERSION')
                IF (InArgs(1)(1:3) == '2.1' .and. ArgFile) THEN
                  CALL ShowWarningError('File is already at latest version.  No new diff file made.',Auditf)
                  CLOSE(diflfn,STATUS='DELETE')
                  LatestVersion=.true.
                  EXIT
                ENDIF
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1)='2.1'
                nodiff=.false.

    !!!    Changes for this version

              CASE('SYSTEM SIZING')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:5)=InArgs(1:5)
                OutArgs(6)='.008'
                OutArgs(7)='11.0'
                OutArgs(8)='.008'
                OutArgs(9:)=InArgs(6:)
                CurArgs=CurArgs+3
                nodiff=.false.

              CASE('HEAT EXCHANGER:DESICCANT:BALANCEDFLOW:PERFORMANCE DATA TYPE 1')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                DO Arg=25,28
                  ErrFlag=.false.
                  SaveNumber=ProcessNumber(OutArgs(Arg),ErrFlag)
                  IF (ErrFlag) THEN
                    CALL ShowSevereError('Invalid Number, HEAT EXCHANGER:DESICCANT:BALANCEDFLOW:PERFORMANCE DATA TYPE 1 field'//  &
                       trim(TrimSigDigits(Arg))//', Name='//TRIM(OutArgs(1)),Auditf)
                    WRITE(DifLfn,fmta) '  ! Invalid Number, field '//TRIM(TrimSigDigits(Arg))//  &
                       ' {'//TRIM(NwFldNames(Arg))//'} contents='//TRIM(OutArgs(Arg))
                  ELSE
                    SaveNumber=SaveNumber*100.0
                    OutArgs(Arg)=TRIM(RoundSigDigits(SaveNumber,1))
                  ENDIF
                ENDDO
                DO Arg=49,52
                  ErrFlag=.false.
                  SaveNumber=ProcessNumber(OutArgs(Arg),ErrFlag)
                  IF (ErrFlag) THEN
                    CALL ShowSevereError('Invalid Number, HEAT EXCHANGER:DESICCANT:BALANCEDFLOW:PERFORMANCE DATA TYPE 1 field'//  &
                       trim(TrimSigDigits(Arg))//', Name='//TRIM(OutArgs(1)),Auditf)
                    WRITE(DifLfn,fmta) '  ! Invalid Number, field '//TRIM(TrimSigDigits(Arg))//  &
                       ' {'//TRIM(NwFldNames(Arg))//'} contents='//TRIM(OutArgs(Arg))
                  ELSE
                    SaveNumber=SaveNumber*100.0
                    OutArgs(Arg)=TRIM(RoundSigDigits(SaveNumber,1))
                  ENDIF
                ENDDO
                nodiff=.false.

              CASE('HEAT EXCHANGER:DESICCANT:BALANCEDFLOW')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                IF (MakeUPPERCase(OutArgs(7)) == 'HEAT EXCHANGER:DESICCANT:BALANCED:PERFORMANCE DATA TYPE 1') THEN
                  nodiff=.false.
                  OutArgs(7)='HEAT EXCHANGER:DESICCANT:BALANCEDFLOW:PERFORMANCE DATA TYPE 1'
                ELSE
                  nodiff=.true.
                ENDIF

              CASE('COMPRESSOR RACK:REFRIGERATED CASE')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:7)=InArgs(1:7)
                OutArgs(8:15)=Blank
                OutArgs(16:CurArgs+8)=InArgs(8:CurArgs)
                CurArgs=CurArgs+8
                nodiff=.false.

              CASE ('DOMESTIC HOT WATER')
                  ! Transition to new object name=> Water Use Equipment
                  ! Put Water connections object first..

                IF (InArgs(2) /= Blank .or. InArgs(3) /= Blank) THEN
                  CALL GetNewObjectDefInIDD('WATER USE CONNECTIONS',NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                  OutArgs(1)=InArgs(1)
                  OutArgs(2:3)=InArgs(2:3)
                  OutArgs(4:6)=Blank
                  OutArgs(7)=InArgs(6)
                  OutArgs(8:10)=Blank
                  OutArgs(11)=InArgs(1)
                  CurArgs=11
                  CALL WriteOutIDFLines(DifLfn,'WATER USE CONNECTIONS',CurArgs,OutArgs,NwFldNames,NwFldUnits)
                ENDIF

                CALL GetNewObjectDefInIDD('WATER USE EQUIPMENT',NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1)=InArgs(1)
                OutArgs(2)=InArgs(7)
                OutArgs(3)=InArgs(4)
                OutArgs(4)=InArgs(5)
                OutArgs(5:6)=Blank
                OutArgs(7)=InArgs(6)
                CurArgs=7
                CALL WriteOutIDFLines(DifLfn,'WATER USE EQUIPMENT',CurArgs,OutArgs,NwFldNames,NwFldUnits)
                Written=.true.
                !CYCLE

              CASE('BRANCH')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                nodiff=.true.
                DO Arg=3,CurArgs,5
                  SELECT CASE (MakeUPPERCase(OutArgs(Arg)))
                    CASE('DOMESTIC HOT WATER')
                      OutArgs(Arg)='Water Use Connections'
                      nodiff=.false.
                    CASE DEFAULT
                  END SELECT
                ENDDO


              CASE('COMPACT HVAC:ZONE:FAN COIL')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.false.
                OutArgs(1:3)=InArgs(1:3)
                OutArgs(4)=Blank
                OutArgs(5)=InArgs(4)
                IF (MakeUPPERCase(InArgs(4)) == 'FLOW/PERSON') THEN
                  OutArgs(6)=InArgs(5)
                ELSE
                  OutArgs(6)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(4)) == 'FLOW/AREA') THEN
                  OutArgs(7)=InArgs(5)
                ELSE
                  OutArgs(7)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(4)) == 'FLOW/ZONE') THEN
                  OutArgs(8)=InArgs(5)
                ELSE
                  OutArgs(8)='0.0'
                ENDIF
                OutArgs(9:19)=InArgs(6:16)
                CurArgs=19

              CASE('COMPACT HVAC:ZONE:UNITARY')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.false.
                OutArgs(1:4)=InArgs(1:4)
                OutArgs(5)=Blank
                OutArgs(6)=InArgs(5)
                IF (MakeUPPERCase(InArgs(5)) == 'FLOW/PERSON') THEN
                  OutArgs(7)=InArgs(6)
                ELSE
                  OutArgs(7)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(5)) == 'FLOW/AREA') THEN
                  OutArgs(8)=InArgs(6)
                ELSE
                  OutArgs(8)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(5)) == 'FLOW/ZONE') THEN
                  OutArgs(9)=InArgs(6)
                ELSE
                  OutArgs(9)='0.0'
                ENDIF
                OutArgs(10:11)=InArgs(7:8)
                OutArgs(12:14)=NwFldDefaults(12:14)
                CurArgs=14

              CASE('COMPACT HVAC:ZONE:VAV')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.false.
                OutArgs(1:4)=InArgs(1:4)
                OutArgs(5)=Blank
                OutArgs(6)=InArgs(5)
                OutArgs(7)=InArgs(6)
                IF (MakeUPPERCase(InArgs(6)) == 'FLOW/PERSON') THEN
                  OutArgs(8)=InArgs(7)
                ELSE
                  OutArgs(8)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(6)) == 'FLOW/AREA') THEN
                  OutArgs(9)=InArgs(7)
                ELSE
                  OutArgs(9)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(6)) == 'FLOW/ZONE') THEN
                  OutArgs(10)=InArgs(7)
                ELSE
                  OutArgs(10)='0.0'
                ENDIF
                OutArgs(11:15)=InArgs(8:12)
                OutArgs(16:18)=NwFldDefaults(16:18)
                CurArgs=18

              CASE('COMPACT HVAC:ZONE:VAV:FAN POWERED')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.false.
                OutArgs(1:4)=InArgs(1:4)
                OutArgs(5)=Blank
                OutArgs(6:10)=InArgs(5:9)
                IF (MakeUPPERCase(InArgs(9)) == 'FLOW/PERSON') THEN
                  OutArgs(11)=InArgs(10)
                ELSE
                  OutArgs(11)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(9)) == 'FLOW/AREA') THEN
                  OutArgs(12)=InArgs(10)
                ELSE
                  OutArgs(12)='0.0'
                ENDIF
                IF (MakeUPPERCase(InArgs(9)) == 'FLOW/ZONE') THEN
                  OutArgs(13)=InArgs(10)
                ELSE
                  OutArgs(13)='0.0'
                ENDIF
                OutArgs(14:20)=InArgs(11:17)
                OutArgs(21:23)=NwFldDefaults(21:23)
                CurArgs=23

              CASE('WATER HEATER:MIXED')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.true.
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                IF (CurArgs >= 31) THEN
                  OutArgs(1:39)=Blank
                  OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                  OutArgs(37)=Blank
                  OutArgs(38)=Blank
                  OutArgs(39)=Blank
                  CurArgs=39
                  nodiff=.false.
                ENDIF

              CASE('WATER HEATER:STRATIFIED')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.true.
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                IF (CurArgs >= 37) THEN
                  OutArgs(1:57)=Blank
                  OutArgs(1:48)=InArgs(1:48)
                  OutArgs(49)=Blank
                  OutArgs(50)=Blank
                  OutArgs(51)=Blank
                  OutArgs(52:CurArgs+3)=InArgs(49:CurArgs)
                  CurArgs=CurArgs+3
                  nodiff=.false.
                ENDIF

              CASE('WINDOWSHADINGCONTROL')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                nodiff=.false.
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                if (samestring('InteriorNonInsulatingShade',InArgs(2))) then
                  OutArgs(2)='InteriorShade'
                endif
                if (samestring('ExteriorNonInsulatingShade',InArgs(2))) then
                  OutArgs(2)='ExteriorShade'
                endif
                if (samestring('InteriorInsulatingShade',InArgs(2))) then
                  OutArgs(2)='InteriorShade'
                endif
                if (samestring('ExteriorInsulatingShade',InArgs(2))) then
                  OutArgs(2)='ExteriorShade'
                endif
                if (samestring('Schedule',InArgs(4))) then
                  OutArgs(4)='OnIfScheduleAllows'
                endif
                if (samestring('SolarOnWindow',InArgs(4))) then
                  OutArgs(4)='OnIfHighSolarOnWindow'
                endif
                if (samestring('HorizontalSolar',InArgs(4))) then
                  OutArgs(4)='OnIfHighHorizontalSolar'
                endif
                if (samestring('OutsideAirTemp',InArgs(4))) then
                  OutArgs(4)='OnIfHighOutsideAirTemp'
                endif
                if (samestring('ZoneAirTemp',InArgs(4))) then
                  OutArgs(4)='OnIfHighZoneAirTemp'
                endif
                if (samestring('ZoneCooling',InArgs(4))) then
                  OutArgs(4)='OnIfHighZoneCooling'
                endif
                if (samestring('Glare',InArgs(4))) then
                  OutArgs(4)='OnIfHighGlare'
                endif
                if (samestring('DaylightIlluminance',InArgs(4))) then
                  OutArgs(4)='MeetDaylightIlluminanceSetpoint'
                endif

    !!!   Changes for report variables, meters, tables -- update names

              CASE ('REPORT VARIABLE')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                nodiff=.true.
                IF (OutArgs(1) == Blank) THEN
                  OutArgs(1)='*'
                  nodiff=.false.
                ENDIF
                CALL ScanOutputVariablesForReplacement(  &
                   2,  &
                   DelThis,  &
                   checkrvi,  &
                   nodiff,  &
                   ObjectName,  &
                   DifLfn,      &
                   .true.,  & !OutVar
                   .false., & !MtrVar
                   .false., & !TimeBinVar
                   CurArgs, &
                   Written, &
                   .false.)
                IF (DelThis) CYCLE

              CASE ('REPORT METER','REPORT METERFILEONLY','REPORT CUMULATIVE METER','REPORT CUMULATIVE METERFILEONLY')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                nodiff=.true.
                CALL ScanOutputVariablesForReplacement(  &
                   1,  &
                   DelThis,  &
                   checkrvi,  &
                   nodiff,  &
                   ObjectName,  &
                   DifLfn,      &
                   .false.,  & !OutVar
                   .true., & !MtrVar
                   .false., & !TimeBinVar
                   CurArgs, &
                   Written, &
                   .false.)
                IF (DelThis) CYCLE

              CASE ('REPORT:TABLE:TIMEBINS')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                nodiff=.true.
                IF (OutArgs(1) == Blank) THEN
                  OutArgs(1)='*'
                  nodiff=.false.
                ENDIF
                CALL ScanOutputVariablesForReplacement(  &
                   2,  &
                   DelThis,  &
                   checkrvi,  &
                   nodiff,  &
                   ObjectName,  &
                   DifLfn,      &
                   .false.,  & !OutVar
                   .false., & !MtrVar
                   .true., & !TimeBinVar
                   CurArgs, &
                   Written, &
                   .false.)
                IF (DelThis) CYCLE

              CASE ('REPORT:TABLE:MONTHLY')
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                nodiff=.true.
                IF (OutArgs(1) == Blank) THEN
                  OutArgs(1)='*'
                  nodiff=.false.
                ENDIF
                CurVar=3
                DO Var=3,CurArgs,2
                  UCRepVarName=MakeUPPERCase(InArgs(Var))
                  OutArgs(CurVar)=InArgs(Var)
                  OutArgs(CurVar+1)=InArgs(Var+1)
                  pos=INDEX(UCRepVarName,'[')
                  IF (pos > 0) THEN
                    UCRepVarName=UCRepVarName(1:pos-1)
                    OutArgs(CurVar)=InArgs(Var)(1:pos-1)
                    OutArgs(CurVar+1)=InArgs(Var+1)
                  ENDIF
                  DelThis=.false.
                  DO Arg=1,NumRepVarNames
                    UCCompRepVarName=MakeUPPERCase(OldRepVarName(Arg))
                    IF (UCCompRepVarName(Len_Trim(UCCompRepVarName):Len_Trim(UCCompRepVarName)) == '*') THEN
                      WildMatch=.true.
                      UCCompRepVarName(Len_Trim(UCCompRepVarName):Len_Trim(UCCompRepVarName))=' '
                    ELSE
                      WildMatch=.false.
                    ENDIF
                    pos=INDEX(TRIM(UCRepVarname),TRIM(UCCompRepVarName))
                    IF (pos > 0 .and. pos /= 1) CYCLE
                    IF (pos > 0) THEN
                      IF (NewRepVarName(Arg) /= '<DELETE>') THEN
                        IF (.not. WildMatch) THEN
                          OutArgs(CurVar)=NewRepVarName(Arg)
                        ELSE
                          OutArgs(CurVar)=TRIM(NewRepVarName(Arg))//OutArgs(CurVar)(Len_Trim(UCCompRepVarName)+1:)
                        ENDIF
                        OutArgs(CurVar+1)=InArgs(Var+1)
                        nodiff=.false.
                      ELSE
                        DelThis=.true.
                      ENDIF
                      IF (OldRepVarName(Arg) == OldRepVarName(Arg+1)) THEN
                        ! Adding a var field.
                        CurVar=CurVar+2
                        IF (.not. WildMatch) THEN
                          OutArgs(CurVar)=NewRepVarName(Arg+1)
                        ELSE
                          OutArgs(CurVar)=TRIM(NewRepVarName(Arg+1))//OutArgs(CurVar)(Len_Trim(UCCompRepVarName)+1:)
                        ENDIF
                        OutArgs(CurVar+1)=InArgs(Var+1)
                        nodiff=.false.
                      ENDIF
                      IF (OldRepVarName(Arg) == OldRepVarName(Arg+2)) THEN
                        ! Adding a var field.
                        CurVar=CurVar+2
                        IF (.not. WildMatch) THEN
                          OutArgs(CurVar)=NewRepVarName(Arg+2)
                        ELSE
                          OutArgs(CurVar)=TRIM(NewRepVarName(Arg+2))//OutArgs(CurVar)(Len_Trim(UCCompRepVarName)+1:)
                        ENDIF
                        OutArgs(CurVar+1)=InArgs(Var+1)
                        nodiff=.false.
                      ENDIF
                      EXIT
                    ENDIF
                  ENDDO
                  IF (.not. DelThis) CurVar=CurVar+2
                ENDDO
                CurArgs=CurVar-1

              CASE DEFAULT
                  IF (FindItemInList(ObjectName,NotInNew,SIZE(NotInNew)) /= 0) THEN
                    WRITE(Auditf,fmta) 'Object="'//TRIM(ObjectName)//'" is not in the "new" IDD.'
                    WRITE(Auditf,fmta) '... will be listed as comments on the new output file.'
                    CALL WriteOutIDFLinesAsComments(DifLfn,ObjectName,CurArgs,InArgs,FldNames,FldUnits)
                    Written=.true.
                    !CYCLE
                  ELSE
                    CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                    OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                    NoDiff=.true.
                  ENDIF

              END SELECT

            ELSE   !!! Making Pretty

              ! Just making pretty -- no changes as above.
              CALL GetNewObjectDefInIDD(IDFRecords(Num)%Name,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
              OutArgs(1:CurArgs)=InArgs(1:CurArgs)
            ENDIF

            IF (DiffMinFields .and. nodiff) THEN
              ! Change in min-fields
                CALL GetNewObjectDefInIDD(ObjectName,NwNumArgs,NwAorN,NwReqFld,NwObjMinFlds,NwFldNames,NwFldDefaults,NwFldUnits)
                OutArgs(1:CurArgs)=InArgs(1:CurArgs)
                NoDiff=.false.
                DO Arg=CurArgs+1,NwObjMinFlds
                  OutArgs(Arg)=NwFldDefaults(Arg)
                ENDDO
                CurArgs=MAX(NwObjMinFlds,CurArgs)
            ENDIF

            IF (NoDiff .and. DiffOnly) CYCLE

            !! reformat for better readability
            !! BUILDING,SOLUTION ALGORITHM,OUTSIDE CONVECTION ALGORITHM,INSIDE CONVECTION ALGORITHM,REPORT VARIABLE,
            !! SURFACE:HEATTRANSFER,SURFACE:HEATTRANSFER:SUBSURFACE:SHADING:DETACHED,
            !! SURFACE:SHADING:DETACHED:FIXED,SURFACE:SHADING:DETACHED:BUILDING,
            !! SURFACE:SHADING:ATTACHED,
            !! WINDOWGLASSSPECTRALDATA,
            !! FLUIDPROPERTYTEMPERATURES,
            !! FLUIDPROPERTYSATURATED,FLUIDPROPERTYSUPERHEATED,FLUIDPROPERTYCONCENTRATION
            IF (.not. Written) THEN
              CALL CheckSpecialObjects(DifLfn,ObjectName,CurArgs,OutArgs,NwFldNames,NwFldUnits,Written)
            ENDIF

            IF (.not. Written) THEN
              CALL WriteOutIDFLines(DifLfn,ObjectName,CurArgs,OutArgs,NwFldNames,NwFldUnits)
            ENDIF

          ENDDO  ! IDFRecords

          IF (NumIDFRecords > 0) THEN
            IF (IDFRecords(NumIDFRecords)%CommtE /= CurComment) THEN
              DO xcount=IDFRecords(NumIDFRecords)%CommtE+1,CurComment
                WRITE(DifLfn,fmta) TRIM(Comments(xcount))
                if (xcount == IDFRecords(Num)%CommtE) WRITE(DifLfn,fmta) ' '
              ENDDO
            ENDIF
          ENDIF

          CLOSE(DifLfn)
          IF (checkrvi) THEN
            CALL ProcessRviMviFiles(FileNamePath,'rvi')
            CALL ProcessRviMviFiles(FileNamePath,'mvi')
          ENDIF
          CALL CloseOut
        ELSE  ! not a idf or imf
          CALL ProcessRviMviFiles(FileNamePath,'rvi')
          CALL ProcessRviMviFiles(FileNamePath,'mvi')
        ENDIF
      ELSE  ! Full name == Blank
        EndOfFile=.true.
      ENDIF

      CALL CreateNewName('Reallocate',CreatedOutputName,' ')

      IF (Allocated(DeleteThisRecord)) THEN
        DEALLOCATE(DeleteThisRecord)
        DEALLOCATE(Alphas)
        DEALLOCATE(Numbers)
        DEALLOCATE(InArgs)
        DEALLOCATE(AorN)
        DEALLOCATE(ReqFld)
        DEALLOCATE(FldNames)
        DEALLOCATE(FldDefaults)
        DEALLOCATE(FldUnits)
        DEALLOCATE(NwAorN)
        DEALLOCATE(NwReqFld)
        DEALLOCATE(NwFldNames)
        DEALLOCATE(NwFldDefaults)
        DEALLOCATE(NwFldUnits)
        DEALLOCATE(OutArgs)
        DEALLOCATE(MatchArg)
      ENDIF

    ENDDO

    IF (.not. ExitBecauseBadFile) THEN
      StillWorking=.false.
      EXIT
    ELSE
      IF (.not. ArgFileBeingDone) THEN
        EndOfFile=.false.
      ELSE
        EndOfFile=.true.
        StillWorking=.false.
      ENDIF
    ENDIF
  ENDDO

  IF (ArgFileBeingDone .and. .not. LatestVersion .and. .not. ExitBecauseBadFile) THEN
    ! If this is true, then there was a "arg IDF File" on the command line and some files need to be
                         ! renamed.
    ErrFlag=.false.
    CALL copyfile(TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension),TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension)//'old',ErrFlag)
!    SysResult=SystemQQ('copy "'//TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension)//'" "'//  &
!                                    TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension)//'old"')
    CALL copyfile(TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension)//'new',TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension),ErrFlag)
!    SysResult=SystemQQ('copy "'//TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension)//'new" "'//  &
!                                  TRIM(FileNamePath)//'.'//TRIM(ArgIDFExtension)//'"')
    INQUIRE(File=TRIM(FileNamePath)//'.rvi',EXIST=FileExist)
    IF (FileExist) THEN
      CALL copyfile(TRIM(FileNamePath)//'.rvi',TRIM(FileNamePath)//'.rviold',ErrFlag)
!      SysResult=SystemQQ('copy "'//TRIM(FileNamePath)//'.rvi" "'//TRIM(FileNamePath)//'.rviold"')
    ENDIF
    INQUIRE(File=TRIM(FileNamePath)//'.rvinew',EXIST=FileExist)
    IF (FileExist) THEN
      CALL copyfile(TRIM(FileNamePath)//'.rvinew',TRIM(FileNamePath)//'.rvi',ErrFlag)
!      SysResult=SystemQQ('copy "'//TRIM(FileNamePath)//'.rvinew" "'//TRIM(FileNamePath)//'.rvi"')
    ENDIF
    INQUIRE(File=TRIM(FileNamePath)//'.mvi',EXIST=FileExist)
    IF (FileExist) THEN
      CALL copyfile(TRIM(FileNamePath)//'.mvi',TRIM(FileNamePath)//'.mviold',ErrFlag)
!      SysResult=SystemQQ('copy "'//TRIM(FileNamePath)//'.mvi" "'//TRIM(FileNamePath)//'.mviold"')
    ENDIF
    INQUIRE(File=TRIM(FileNamePath)//'.mvinew',EXIST=FileExist)
    IF (FileExist) THEN
      CALL copyfile(TRIM(FileNamePath)//'.mvinew',TRIM(FileNamePath)//'.mvi',ErrFlag)
!      SysResult=SystemQQ('copy "'//TRIM(FileNamePath)//'.mvinew" "'//TRIM(FileNamePath)//'.mvi"')
    ENDIF
  ENDIF

  RETURN

END SUBROUTINE CreateNewIDFUsingRules
