{
        File: uFavoritesManager.pas
        License: GPLv2
        This unit is a part of Free Manga Downloader
}

unit uFavoritesManager;

{$mode delphi}

interface

uses
  Classes, SysUtils, fgl, Dialogs, ExtCtrls,
  LazFileUtils, uBaseUnit, uData, uDownloadsManager, WebsiteModules, FMDOptions,
  httpsendthread, FavoritesDB, BaseThread, SimpleException, VirtualTrees;

type
  TFavoriteManager = class;
  TFavoriteTask = class;
  TfavoriteContainer = class;

  { TFavoriteThread }

  TFavoriteThread = class(TBaseThread)
  private
    FMangaInformation: TMangaInformation;
  protected
    procedure Execute; override;
  public
    WorkId: Cardinal;
    Task: TFavoriteTask;
    Container: TfavoriteContainer;
    constructor Create;
    destructor Destroy; override;
  end;

  TFavoriteThreads = TFPGList<TFavoriteThread>;

  { TFavoriteTask }

  TFavoriteTask = class(TBaseThread)
  private
    FBtnCaption: String;
    FPendingCount: Integer;
    FNeedRepaint: Integer;
    FTimerRepaint: TTimer;
  protected
    procedure TimerRepaintOnTimer(Sender: TObject);
    procedure SyncStartChecking;
    procedure SyncFinishChecking;
    procedure SyncUpdateBtnCaption;
    procedure Checkout;
    procedure Execute; override;
    procedure UpdateStatus;
  public
    CS_Threads: TRTLCriticalSection;
    Manager: TFavoriteManager;
    Threads: TFavoriteThreads;
    procedure UpdateBtnCaption(Cap: String);
    constructor Create;
    destructor Destroy; override;
  end;

  { TFavoriteContainer }

  TFavoriteContainer = class
  private
    FEnabled: Boolean;
    procedure SetEnabled(AValue: Boolean);
  public
    Tag: Integer;
    FavoriteInfo: TFavoriteInfo;
    NewMangaInfo: TMangaInfo;
    NewMangaInfoChaptersPos: TCardinalList;
    Thread: TFavoriteThread;
    Manager: TFavoriteManager;
    Status: TFavoriteStatusType;
    constructor Create;
    destructor Destroy; override;
    procedure SaveToDB(const AOrder: Integer = -1);
    property Enabled: Boolean read FEnabled write SetEnabled;
  end;

  TFavoriteContainers = TFPGList<TFavoriteContainer>;

  { TFavoriteManager }

  TFavoriteManager = class
  private
    CS_Favorites: TRTLCriticalSection;
    FFavoritesDB: TFavoritesDB;
    FSortColumn: Integer;
    FSortDirection, FIsAuto, FIsRunning: Boolean;
    function GetFavoritesCount: Integer; inline;
    function GetEnabledFavoritesCount: Integer; inline;
    function GetDisabledFavoritesCount: Integer; inline;
    function GetFavorite(const Index: Integer): TFavoriteContainer;
  public
    Items: TFavoriteContainers;
    TaskThread: TFavoriteTask;
    DLManager: TDownloadManager;
    OnUpdateFavorite: procedure of object;
    OnUpdateDownload: procedure of object;

    constructor Create;
    destructor Destroy; override;

    //Check favorites
    procedure CheckForNewChapter(FavoriteIndex: Integer = -1);
    procedure StopChekForNewChapter(WaitFor: Boolean = True; FavoriteIndex: Integer = -1);

    // Show notification form after checking completed
    procedure ShowResult;
    // Return true if a manga exist in favorites
    function LocateManga(const ATitle, AWebsite: String): TFavoriteContainer;
    function IsMangaExist(const ATitle, AWebsite: String): Boolean; inline;
    function LocateMangaByLink(const AModuleID, ALink: String): TFavoriteContainer;
    function IsMangaExistByLink(const AModuleID, ALink: String): Boolean; inline;
    // Add new manga to the list
    procedure Add(const AModule: Pointer; const ATitle, AStatus, ACurrentChapter, ADownloadedChapterList, ASaveTo, ALink: String);
    // Merge manga information with a title that already exist in favorites
    procedure AddMerge(const ATitle, ACurrentChapter, ADownloadedChapterList, AWebsite,
      ASaveTo, ALink: String);
    // Free then delete favorite without any check, use with caution
    procedure FreeAndDelete(const Pos: Integer); overload;
    procedure FreeAndDelete(const T: TFavoriteContainer); overload;
    // Remove a manga from FFavorites
    procedure Remove(const Pos: Integer; const isBackup: Boolean = True); overload;
    procedure Remove(const T: TFavoriteContainer; const isBackup: Boolean = True); overload;
    // Restore information from favorites.db
    procedure Restore;
    // Backup to favorites.db
    procedure Backup;
    // Add FFavorites downloadedchapterlist
    procedure AddToDownloadedChaptersList(const AWebsite, ALink: String; const AValue: TStrings);
    // sorting
    procedure Sort(const AColumn: Integer);
    // critical section
    procedure Lock;
    procedure LockRelease;
    procedure SearchEnabledOnVT(Tree: TVirtualStringTree; Key: String);
    procedure SearchDisabledOnVT(Tree: TVirtualStringTree; Key: String);

    property Count: Integer read GetFavoritesCount;
    property CountEnabled: Integer read GetEnabledFavoritesCount;
    property CountDisabled: Integer read GetDisabledFavoritesCount;
    property SortDirection: Boolean read FSortDirection write FSortDirection;
    property SortColumn: Integer read FSortColumn write FSortColumn;
    property isAuto: Boolean read FIsAuto write FIsAuto;
    property isRunning: Boolean read FIsRunning write FIsRunning;
    property Favorite[const Index: Integer]: TFavoriteContainer read GetFavorite; default;
  end;

resourcestring
  RS_DlgFavoritesCheckIsRunning = 'Favorites check is running!';
  RS_DlgNewChapterCaption = '%d manga(s) have new chapter(s)';
  RS_LblNewChapterFound = 'Found %d new chapter from %d manga(s):';
  RS_FavoriteHasNewChapter = '%s <%s> has %d new chapter(s).';
  RS_BtnDownload = '&Download';
  RS_BtnAddToQueue = '&Add to queue';
  RS_BtnCancel = '&Cancel';
  RS_DlgCompletedMangaCaption = 'Found %d completed manga';
  RS_LblMangaWillBeRemoved = 'Completed manga will be removed:';
  RS_BtnRemove = '&Remove';
  RS_BtnCheckFavorites = 'Check for new chapter';

implementation

uses
  frmMain, frmNewChapter, FMDVars, DateUtils;

{ TFavoriteContainer }

procedure TFavoriteContainer.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
end;

constructor TFavoriteContainer.Create;
begin
  FEnabled := True;
  Tag := 0;
end;

destructor TFavoriteContainer.Destroy;
begin
  if Assigned(Thread) then
  begin
    Thread.Terminate;
    Thread.WaitFor;
    Thread := nil;
  end;
  if Assigned(NewMangaInfo) then
  begin
    NewMangaInfo.Free;
    NewMangaInfoChaptersPos.Free;
  end;
  inherited Destroy;
end;

procedure TFavoriteContainer.SaveToDB(const AOrder: Integer);
var
  i: Integer;
begin
  if AOrder = -1 then
    i := Manager.Items.IndexOf(Self)
  else
    i := AOrder;
  with FavoriteInfo do
    Manager.FFavoritesDB.Add(
      i,
      FEnabled,
      ModuleID,
      Link,
      Title,
      Status,
      CurrentChapter,
      DownloadedChapterList,
      SaveTo,
      DateAdded
      );
end;

{ TFavoriteThread }

procedure TFavoriteThread.Execute;
var
  DLChapters: TStringList;
  i: Integer;
begin
  if (Container.FavoriteInfo.Link) = '' then Exit;

  Task.UpdateStatus;
  with Container do
    try
      FMangaInformation.Module := FavoriteInfo.Module;
      // get new manga info
      FMangaInformation.isGetByUpdater := False;
      //FMangaInformation.MangaInfo.Title := FavoriteInfo.Title; // retrieve the original title so custom rename can remove them
      FMangaInformation.GetInfoFromURL(FavoriteInfo.Link);
      if not Terminated then
      begin
        NewMangaInfo := FMangaInformation.MangaInfo;
        FMangaInformation.MangaInfo := nil;
        NewMangaInfoChaptersPos := TCardinalList.Create;
        // update current chapters count immedietly
        FavoriteInfo.CurrentChapter := IntToStr(NewMangaInfo.ChapterLinks.Count);
        FavoriteInfo.Status := NewMangaInfo.Status;
        if NewMangaInfo.ChapterLinks.Count > 0 then
        begin
          // tag 100 for transfer favorite, add all chapter to downloaded chapter list
          if Container.Tag = 100 then
          begin
            FavoriteInfo.DownloadedChapterList := NewMangaInfo.ChapterLinks.Text;
            Container.Tag := 0;
          end
          else
          try
            DLChapters := TStringList.Create;
            DLChapters.Sorted := False;
            DLChapters.Text := FavoriteInfo.DownloadedChapterList;
            DLChapters.Sorted := True;
            for i := 0 to NewMangaInfo.ChapterLinks.Count - 1 do
              if DLChapters.IndexOf(NewMangaInfo.ChapterLinks[i]) = -1 then
                NewMangaInfoChaptersPos.Add(i);
          finally
            DLChapters.Free;
          end;
        end;

        if not Terminated then
        begin
          Container.FavoriteInfo.DateLastChecked := Now;
          if (NewMangaInfoChaptersPos.Count <> 0) then
            Container.FavoriteInfo.DateLastUpdated := Now;
        end;

        // free unneeded objects
        if (NewMangaInfoChaptersPos.Count = 0) and
          (NewMangaInfo.Status <> MangaInfo_StatusCompleted) then
        begin
          FreeAndNil(NewMangaInfo);
          FreeAndNil(NewMangaInfoChaptersPos);
        end;
      end;
    except
      on E: Exception do
        ExceptionHandle(Self, E);
    end;
end;

constructor TFavoriteThread.Create;
begin
  inherited Create(True);
  FMangaInformation := TMangaInformation.Create(Self);
end;

destructor TFavoriteThread.Destroy;
begin
  if Terminated then
  begin
    Container.Status := STATUS_IDLE;
    // free unused objects
    if Assigned(Container.NewMangaInfo) then
    begin
      FreeAndNil(Container.NewMangaInfo);
      FreeAndNil(Container.NewMangaInfoChaptersPos);
    end;
  end
  else
    Container.Status := STATUS_CHECKED;
  Container.Thread := nil;

  EnterCriticalsection(Task.CS_Threads);
  try
    Task.Threads.Remove(Self);
  finally
    LeaveCriticalsection(Task.CS_Threads);
  end;
  FMangaInformation.Free;
  if not Terminated then
    Task.UpdateStatus;
  inherited Destroy;
end;

{ TFavoriteTask }

procedure TFavoriteTask.TimerRepaintOnTimer(Sender: TObject);
begin
  if FNeedRepaint > 0 then
  begin
    InterlockedExchange(FNeedRepaint, 0);
    FormMain.vtFavorites.Repaint;
  end;
end;

procedure TFavoriteTask.SyncStartChecking;
begin
  with MainForm do begin
    btCancelFavoritesCheck.Visible := True;
    btFavoritesCheckNewChapter.Width :=
      btFavoritesCheckNewChapter.Width - btCancelFavoritesCheck.Width - 6;
    btFavoritesCheckNewChapter.Caption := RS_Checking;
    rbFavoritesShowAll.Enabled := False;
    rbFavoritesShowDisabled.Enabled := False;
    rbFavoritesShowEnabled.Enabled := False;
  end;
end;

procedure TFavoriteTask.SyncFinishChecking;
begin
  with MainForm do
  begin
    btCancelFavoritesCheck.Visible := False;
    btFavoritesCheckNewChapter.Width := btFavoritesCheckNewChapter.Width +
      btCancelFavoritesCheck.Width + 6;
    btFavoritesCheckNewChapter.Caption := RS_BtnCheckFavorites;
    rbFavoritesShowAll.Enabled := True;
    rbFavoritesShowDisabled.Enabled := True;
    rbFavoritesShowEnabled.Enabled := True;
    vtFavorites.Repaint;
    if OptionAutoCheckFavInterval and (not tmCheckFavorites.Enabled) then
      tmCheckFavorites.Enabled := True;
  end;
end;

procedure TFavoriteTask.SyncUpdateBtnCaption;
begin
  MainForm.btFavoritesCheckNewChapter.Caption := FBtnCaption;
end;

procedure TFavoriteTask.Checkout;
var
  i: Integer;
begin
  if Terminated then Exit;
  if Manager.Items.Count = 0 then Exit;

  FPendingCount := 0;
  for i := 0 to Manager.Items.Count - 1 do
  begin
    if Terminated then Break;
    with Manager.Items[i] do
      if (Status = STATUS_CHECK) then
      begin
        if FavoriteInfo.Module = nil then
          Status := STATUS_IDLE
        else
        if (Threads.Count < OptionMaxThreads) then
        begin
          EnterCriticalsection(CS_Threads);
          try
            Status := STATUS_CHECKING;
            Thread := TFavoriteThread.Create;
            Threads.Add(Thread);
            Thread.Task := Self;
            Thread.Container := Manager.Items[i];
            Thread.WorkId := i;
            Thread.Start;
          finally
            LeaveCriticalsection(CS_Threads);
          end
        end
        else
          Inc(FPendingCount);
      end;
  end;
end;

procedure TFavoriteTask.Execute;
var
  cthread,
  cmaxthreads: Integer;
begin
  Manager.isRunning := True;
  Synchronize(SyncStartChecking);
  try
    while not Terminated do
    begin
      cmaxthreads := OptionMaxThreads;
      // if current thread count > max Threads allowed we wait until thread count decreased
      while (not Terminated) and (Threads.Count >= cmaxthreads) do
        Sleep(HeartBeatRate);
      Checkout;
      // if there is concurent connection limit applied and no more possible item to check
      // we will wait until thread count decreased
      // break wait if OptionMaxThreads changed
      cthread := Threads.Count;
      while (not Terminated) and (Threads.Count > 0) and (Threads.Count = cthread) and
        (cmaxthreads = OptionMaxThreads) do
        Sleep(HeartBeatRate);
      // if there is no more item need to be checked, but thread count still > 0 we will wait for it
      // we will also wait if there is new item pushed, so we will check it after it
      while (not Terminated) and (FPendingCount = 0) and (Threads.Count > 0) do
        Sleep(HeartBeatRate);
      if FPendingCount = 0 then Break;
    end;

    while (not Terminated) and (Threads.Count <> 0) do
      Sleep(HeartBeatRate);
  except
    on E: Exception do
      ExceptionHandle(Self, E);
  end;
end;

procedure TFavoriteTask.UpdateBtnCaption(Cap: String);
begin
  FBtnCaption := Cap;
  Synchronize(SyncUpdateBtnCaption);
end;

constructor TFavoriteTask.Create;
begin
  inherited Create(True);
  InitCriticalSection(CS_Threads);
  Threads := TFavoriteThreads.Create;

  FNeedRepaint := 0;
  FTimerRepaint := TTimer.Create(nil);
  FTimerRepaint.Interval := 500;
  FTimerRepaint.OnTimer := TimerRepaintOnTimer;
  FTimerRepaint.Enabled := True;
end;

destructor TFavoriteTask.Destroy;
var
  i: Integer;
begin
  // reset all status
  EnterCriticalsection(Manager.CS_Favorites);
  try
    for i := 0 to Manager.Items.Count - 1 do
      Manager.Items[i].Status := STATUS_IDLE;
  finally
    LeaveCriticalsection(Manager.CS_Favorites);
  end;

  // terminate all threads and wait
  EnterCriticalsection(CS_Threads);
  try
    if Threads.Count > 0 then
      for i := 0 to Threads.Count - 1 do
        Threads[i].Terminate;
  finally
    LeaveCriticalsection(CS_Threads);
  end;
  while Threads.Count > 0 do
    Sleep(32);

  if (not Terminated) and (not isDlgCounter) then
    Synchronize(Manager.ShowResult)
  else
  // free unused unit
  begin
    EnterCriticalsection(Manager.CS_Favorites);
    try
      for i := 0 to Manager.Items.Count - 1 do
        with Manager.Items[i] do
        begin
          if Assigned(NewMangaInfo) then
            FreeAndNil(NewMangaInfo);
          if Assigned(NewMangaInfoChaptersPos) then
            FreeAndNil(NewMangaInfoChaptersPos);
        end;
    finally
      LeaveCriticalsection(Manager.CS_Favorites);
    end;
  end;

  Threads.Free;
  try
    EnterCriticalsection(Manager.CS_Favorites);
    Manager.isRunning := False;
    Manager.TaskThread := nil;
  finally
    LeaveCriticalsection(Manager.CS_Favorites);
  end;

  FTimerRepaint.Free;

  // reset the ui
  if not isExiting then
    Synchronize(SyncFinishChecking);
  inherited Destroy;
end;

procedure TFavoriteTask.UpdateStatus;
begin
  InterlockedIncrement(FNeedRepaint);
end;

{ TFavoriteManager }

function TFavoriteManager.GetFavoritesCount: Integer;
begin
  Result := Items.Count;
end;

function TFavoriteManager.GetEnabledFavoritesCount: Integer;
var
  i: Integer;
  j: Integer;
begin
  j := 0;
  for i := 0 to Items.Count - 1 do
  begin
    if Items[i].FEnabled then j := j + 1;
  end;
  Result := j;
end;

function TFavoriteManager.GetDisabledFavoritesCount: Integer;
var
  i: Integer;
  j: Integer;
begin
  j := 0;
  for i := 0 to Items.Count - 1 do
  begin
    if not Items[i].FEnabled then j := j + 1;
  end;
  Result := j;
end;

procedure TFavoriteManager.SearchEnabledOnVT(Tree: TVirtualStringTree; Key: String);
var
  s: String;
  node, xnode: PVirtualNode;
  v: Boolean;
begin
  if Tree.TotalCount = 0 then
    Exit;
  s := AnsiUpperCase(Key);
  Tree.BeginUpdate;
  try
    node := Tree.GetFirst();
    if (s <> '') then
    begin
      while node <> nil do
      begin
        v := Pos(s, AnsiUpperCase(Tree.Text[node, 1])) <> 0;
        if FavoriteManager[node^.Index].Enabled then
          Tree.IsVisible[node] := v;
        if v then
        begin
          xnode := node^.Parent;
          while (xnode <> nil)  and (xnode <> Tree.RootNode) do
          begin
            if not (vsVisible in xnode^.States) and (FavoriteManager[node^.Index].Enabled) then
              Tree.IsVisible[xnode] := True;
            xnode := xnode^.Parent;
          end;
        end;
        node := Tree.GetNext(node);
      end;
    end
    else
    begin
      while node <> nil do
      begin
        if (FavoriteManager[node^.Index].Enabled) then
          Tree.IsVisible[node] := True
        else
          Tree.IsVisible[node] := False;
        node := Tree.GetNext(node);
      end;
    end;
  finally
    Tree.EndUpdate;
  end;
end;

procedure TFavoriteManager.SearchDisabledOnVT(Tree: TVirtualStringTree; Key: String);
var
  s: String;
  node, xnode: PVirtualNode;
  v: Boolean;
begin
  if Tree.TotalCount = 0 then
    Exit;
  s := AnsiUpperCase(Key);
  Tree.BeginUpdate;
  try
    node := Tree.GetFirst();
    if (s <> '') then
    begin
      while node <> nil do
      begin
        v := Pos(s, AnsiUpperCase(Tree.Text[node, 1])) <> 0;
        if not FavoriteManager[node^.Index].Enabled then
          Tree.IsVisible[node] := v;
        if v then
        begin
          xnode := node^.Parent;
          while (xnode <> nil)  and (xnode <> Tree.RootNode) do
          begin
            if not ((vsVisible in xnode^.States) and (FavoriteManager[node^.Index].Enabled)) then
              Tree.IsVisible[xnode] := True;
            xnode := xnode^.Parent;
          end;
        end;
        node := Tree.GetNext(node);
      end;
    end
    else
    begin
      while node <> nil do
      begin
        if not (FavoriteManager[node^.Index].Enabled) then
          Tree.IsVisible[node] := True
        else
          Tree.IsVisible[node] := False;
        node := Tree.GetNext(node);
      end;
    end;
  finally
    Tree.EndUpdate;
  end;
end;

function TFavoriteManager.GetFavorite(const Index: Integer): TFavoriteContainer;
begin
  Result := Items[Index];
end;

constructor TFavoriteManager.Create;
begin
  inherited Create;
  ForceDirectories(USERDATA_FOLDER);
  InitCriticalSection(CS_Favorites);
  isRunning := False;
  Items := TFavoriteContainers.Create;;
  FFavoritesDB := TFavoritesDB.Create(FAVORITESDB_FILE);
  FFavoritesDB.Open;
end;

destructor TFavoriteManager.Destroy;
var
  i: Integer;
begin
  if Items.Count > 0 then
  begin
    StopChekForNewChapter;
    for i := 0 to Items.Count - 1 do
      Items[i].Free;
  end;
  Items.Free;
  FFavoritesDB.Free;
  DoneCriticalsection(CS_Favorites);
  inherited Destroy;
end;

procedure TFavoriteManager.CheckForNewChapter(FavoriteIndex: Integer);
var
  i: Integer;
  toCheckCount: Integer;
begin
  if isDlgCounter then Exit;
  try
    toCheckCount := 0;
    if FavoriteIndex > -1 then
    begin
      with Items[FavoriteIndex] do
        if Assigned(FavoriteInfo.Module) and FEnabled and (Status = STATUS_IDLE) then
        begin
          Status := STATUS_CHECK;
          Inc(toCheckCount);
          if Assigned(TaskThread) then
            InterLockedIncrement(TaskThread.FPendingCount);
        end;
    end
    else
    if isRunning then
    begin
      if not isAuto then
        MessageDlg('', RS_DlgFavoritesCheckIsRunning, mtInformation, [mbOK], 0);
    end
    else
    begin
      EnterCriticalsection(CS_Favorites);
      try
        for i := 0 to Items.Count - 1 do
          with Items[i] do
            if Assigned(FavoriteInfo.Module) and FEnabled and (Status = STATUS_IDLE) and (Trim(FavoriteInfo.Link) <> '') then
            begin
              Status := STATUS_CHECK;
              Inc(toCheckCount);
            end;
      finally
        LeaveCriticalsection(CS_Favorites);
      end;
    end;
    if (toCheckCount > 0) and (TaskThread = nil) then
    begin
      TaskThread := TFavoriteTask.Create;
      TaskThread.Manager := Self;
      TaskThread.Start;
    end;
  except
    on E: Exception do
      ExceptionHandle(Self, E);
  end;
end;

procedure TFavoriteManager.StopChekForNewChapter(WaitFor: Boolean; FavoriteIndex: Integer);
begin
  if not isRunning then Exit;
  if FavoriteIndex > -1 then
  begin
    with Items[FavoriteIndex] do begin
      if Thread <> nil then
      begin
        Thread.Terminate;
        if WaitFor then
          Thread.WaitFor;
      end;
      if Status <> STATUS_IDLE then
        Status := STATUS_IDLE;
    end;
  end
  else
  if Assigned(TaskThread) then
  begin
    TaskThread.Terminate;
    if WaitFor then
      TaskThread.WaitFor;
  end;
end;

procedure TFavoriteManager.ShowResult;
var
  i, j,
  numOfNewChapters,
  numOfMangaNewChapters,
  numOfCompleted: Integer;
  LNCResult: TNewChapterResult = ncrCancel;
  newChapterListStr: String = '';
  removeListStr: String = '';
  newdl: LongInt;
begin
  if isDlgCounter then Exit;
  if (Self.DLManager = nil) and Assigned(DLManager) then
    Self.DLManager := DLManager;
  if Self.DLManager = nil then Exit;

  Self.Sort(Self.FSortColumn);
  EnterCriticalsection(CS_Favorites);
  try
    numOfNewChapters := 0;
    numOfMangaNewChapters := 0;
    numOfCompleted := 0;

    try
      // check for all favorites
      for i := 0 to Items.Count - 1 do
        with Items[i] do
          if Assigned(NewMangaInfo) then
          begin
            // new chapters add to notification
            if NewMangaInfoChaptersPos.Count > 0 then
            begin
              newChapterListStr += LineEnding + '- ' + Format(
                RS_FavoriteHasNewChapter, [FavoriteInfo.Title, FavoriteInfo.Website,
                NewMangaInfoChaptersPos.Count]);
              Inc(numOfMangaNewChapters);
              Inc(numOfNewChapters, NewMangaInfoChaptersPos.Count);
            end
            else
            // completed series add to notification
            if OptionAutoCheckFavRemoveCompletedManga and
              (NewMangaInfo.Status = MangaInfo_StatusCompleted) then
            begin
              removeListStr += LineEnding + Format('- %s <%s>',
                [FavoriteInfo.Title, FavoriteInfo.Website]);
              Inc(numOfCompleted);
            end;
          end;

      // if there is completed mangas, show dialog
      if numOfCompleted > 0 then
      begin
        with TNewChapter.Create(MainForm) do
          try
            Caption := Format(RS_DlgCompletedMangaCaption, [numOfCompleted]);
            lbNotification.Caption := RS_LblMangaWillBeRemoved;
            mmMemo.Lines.Text := Trim(removeListStr);
            btDownload.Caption := RS_BtnRemove;
            btCancel.Caption := RS_BtnCancel;
            btDownload.Show;
            btCancel.Show;
            btQueue.Hide;
            ShowModal;
            LNCResult := FormResult;
          finally
            Free;
          end;

        //delete complete FFavorites
        if LNCResult = ncrDownload then
        begin
          i := 0;
          while i < Items.Count do
            with Items[i] do
            begin
              if Assigned(NewMangaInfo) and
                (NewMangaInfoChaptersPos.Count = 0) and
                (NewMangaInfo.Status = MangaInfo_StatusCompleted) then
                FreeAndDelete(i)
              else
                Inc(i);
            end;
        end;
        Backup;
      end;

      // if there is new chapters
      if numOfNewChapters > 0 then
      begin
        if OptionAutoCheckFavDownload then
          LNCResult := ncrDownload
        else
          with TNewChapter.Create(MainForm) do
            try
              Caption := Format(RS_DlgNewChapterCaption, [numOfNewChapters]);
              lbNotification.Caption :=
                Format(RS_LblNewChapterFound, [numOfNewChapters, numOfMangaNewChapters]);
              mmMemo.Lines.Text := Trim(newChapterListStr);
              btDownload.Caption := RS_BtnDownload;
              btQueue.Caption := RS_BtnAddToQueue;
              btCancel.Caption := RS_BtnCancel;
              btDownload.Show;
              btQueue.Show;
              btCancel.Show;
              ShowModal;
              LNCResult := FormResult;
            finally
              Free;
            end;

        // generate download task
        if LNCResult <> ncrCancel then
        begin
          while DLManager.isRunningBackup do
            Sleep(100);

          for i := 0 to Items.Count - 1 do
            with Items[i] do
              if Assigned(NewMangaInfo) and
                (NewMangaInfoChaptersPos.Count > 0) then
                try
                  EnterCriticalSection(DLManager.CS_Task);
                  newdl := DLManager.Items.Add(TTaskContainer.Create);
                  with DLManager.Items[newdl] do
                  begin
                    Manager := DLManager;
                    CurrentDownloadChapterPtr := 0;
                    DownloadInfo.Module := FavoriteInfo.Module;
                    DownloadInfo.Link := FavoriteInfo.Link;
                    DownloadInfo.Title := FavoriteInfo.Title;
                    DownloadInfo.SaveTo := FavoriteInfo.SaveTo;
                    DownloadInfo.DateAdded := Now;
                    DownloadInfo.DateLastDownloaded := Now;

                    for j := 0 to NewMangaInfoChaptersPos.Count - 1 do
                    begin
                      ChapterLinks.Add(NewMangaInfo.ChapterLinks[NewMangaInfoChaptersPos[j]]);
                      ChapterNames.Add(CustomRename(
                        OptionChapterCustomRename,
                        FavoriteInfo.Website,
                        FavoriteInfo.Title,
                        NewMangaInfo.Authors,
                        NewMangaInfo.Artists,
                        NewMangaInfo.ChapterNames[NewMangaInfoChaptersPos[j]],
                        Format('%.4d', [NewMangaInfoChaptersPos[j] + 1]),
                        OptionChangeUnicodeCharacter,
                        OptionChangeUnicodeCharacterStr));
                    end;

                    if LNCResult = ncrDownload then
                    begin
                      DownloadInfo.Status := Format('[%d/%d] %s',[0,ChapterLinks.Count,RS_Waiting]);
                      Status := STATUS_WAIT;
                    end
                    else
                    begin
                      DownloadInfo.Status := Format('[%d/%d] %s',[0,ChapterLinks.Count,RS_Stopped]);
                      Status := STATUS_STOP;
                    end;
                    SaveToDB(newdl);
                    // add to downloaded chapter list
                    FavoriteInfo.downloadedChapterList := MergeCaseInsensitive([FavoriteInfo.DownloadedChapterList, chapterLinks.Text]);
                    // add to downloaded chapter list in downloadmanager
                    DLManager.DownloadedChapters.Chapters[FavoriteInfo.ModuleID, FavoriteInfo.Link] := chapterLinks.Text;
                  end;
                  // free unused objects
                  FreeAndNil(NewMangaInfo);
                  FreeAndNil(NewMangaInfoChaptersPos);
                finally
                  LeaveCriticalSection(DLManager.CS_Task);
                end;

          Backup;
          if LNCResult = ncrDownload then
          begin
            DLManager.CheckAndActiveTask;
            if OptionSortDownloadsWhenAddingNewDownloadTasks then
              DLManager.Sort(DLManager.SortColumn);
            if OptionShowDownloadsTabOnNewTasks then
              MainForm.pcMain.ActivePage := MainForm.tsDownload;
          end;
          if Assigned(OnUpdateDownload) then
            OnUpdateDownload;
          if Assigned(OnUpdateFavorite) then
            OnUpdateFavorite;
        end;
      end;

    except
      on E: Exception do
        ExceptionHandle(Self, E);
    end;

    // check again for unused objects and free them
    for i := 0 to Items.Count - 1 do
      with Items[i] do
        if Assigned(NewMangaInfo) then
        begin
          FreeAndNil(NewMangaInfo);
          FreeAndNil(NewMangaInfoChaptersPos);
        end;
  finally
    LeaveCriticalsection(CS_Favorites);
  end;
end;

function TFavoriteManager.LocateManga(const ATitle, AWebsite: String): TFavoriteContainer;
var
  i: Integer;
begin
  Result := nil;
  if Items.Count <> 0 then
    for i := 0 to Items.Count - 1 do
      with Items[i].FavoriteInfo do
        if SameText(ATitle, Title) and SameText(AWebsite, ModuleID) then
          Exit(Items[i]);
end;

function TFavoriteManager.IsMangaExist(const ATitle, AWebsite: String): Boolean;
begin
  Result := LocateManga(ATitle, AWebsite) <> nil;
end;

function TFavoriteManager.LocateMangaByLink(const AModuleID, ALink: String): TFavoriteContainer;
var
  i: Integer;
begin
  Result := nil;
  if Items.Count <> 0 then
    for i := 0 to Items.Count - 1 do
      with Items[i].FavoriteInfo do
        if SameText(AModuleID, ModuleID) and SameText(ALink, Link) then
          Exit(Items[i]);
end;

function TFavoriteManager.IsMangaExistByLink(const AModuleID, ALink: String): Boolean;
begin
  Result := LocateMangaByLink(AModuleID, ALink) <> nil;
end;

procedure TFavoriteManager.Add(const AModule: Pointer; const ATitle, AStatus, ACurrentChapter,
  ADownloadedChapterList, ASaveTo, ALink: String);
var
  newfv: Integer;
begin
  if AModule = nil then Exit;
  if IsMangaExist(ATitle, TModuleContainer(AModule).ID) then Exit;
  EnterCriticalsection(CS_Favorites);
  try
    newfv := Items.Add(TFavoriteContainer.Create);
    with Items[newfv] do begin
      Manager := Self;
      with FavoriteInfo do begin
        Module := AModule;
        Title := ATitle;
        Status := AStatus;
        CurrentChapter := ACurrentChapter;
        SaveTo := ASaveTo;
        Link := ALink;
        DownloadedChapterList := ADownloadedChapterList;
        DateAdded := Now;
        DateLastChecked := Now;
        DateLastUpdated := Now;
      end;
      Status := STATUS_IDLE;
      SaveToDB(newfv);
    end;
    if not isRunning then
      Sort(SortColumn);
  finally
    LeaveCriticalsection(CS_Favorites);
  end;
end;

procedure TFavoriteManager.AddMerge(const ATitle, ACurrentChapter, ADownloadedChapterList,
  AWebsite, ASaveTo, ALink: String);
begin
  if IsMangaExist(ATitle, AWebsite) then
    Exit;
  EnterCriticalsection(CS_Favorites);
  try
    Items.Add(TFavoriteContainer.Create);
    with Items.Last do begin
      Manager := Self;
      with FavoriteInfo do begin
        ModuleID := AWebsite;
        Title := ATitle;
        CurrentChapter := ACurrentChapter;
        SaveTo := ASaveTo;
        Link := ALink;
        DownloadedChapterList := ADownloadedChapterList;
      end;
    end;
  except
    LeaveCriticalsection(CS_Favorites);
  end;
end;

procedure TFavoriteManager.FreeAndDelete(const Pos: Integer);
begin
  with Items[Pos].FavoriteInfo do
    FFavoritesDB.Delete(ModuleID, Link);
  Items[Pos].Free;
  Items.Delete(Pos);
end;

procedure TFavoriteManager.FreeAndDelete(const T: TFavoriteContainer);
begin
  with T.FavoriteInfo do
    FFavoritesDB.Delete(ModuleID, Link);
  T.Free;
  Items.Remove(T);
end;

procedure TFavoriteManager.Remove(const Pos: Integer; const isBackup: Boolean);
begin
  if (not isRunning) and (Pos < Items.Count) then
  begin
    EnterCriticalsection(CS_Favorites);
    try
      FreeAndDelete(Pos);
      if isBackup then
        Backup;
    finally
      LeaveCriticalsection(CS_Favorites);
    end;
  end;
end;

procedure TFavoriteManager.Remove(const T: TFavoriteContainer; const isBackup: Boolean);
begin
  if not isRunning then
  begin
    EnterCriticalsection(CS_Favorites);
    try
      FreeAndDelete(T);
      if isBackup then
        Backup;
    finally
      LeaveCriticalsection(CS_Favorites);
    end;
  end;
end;

procedure TFavoriteManager.Restore;
begin
  if not FFavoritesDB.Connection.Connected then Exit;
  if FFavoritesDB.OpenTable(False) then
    try
      if FFavoritesDB.Table.RecordCount = 0 then Exit;
      EnterCriticalsection(CS_Favorites);
      try
        FFavoritesDB.Table.Last; //load all to memory
        FFavoritesDB.Table.First;
        while not FFavoritesDB.Table.EOF do
        begin
          with Items[Items.Add(TFavoriteContainer.Create)], FFavoritesDB.Table do
            begin
              Manager                            := Self;
              Status                             := STATUS_IDLE;
              Enabled                            := Fields[f_enabled].AsBoolean;
              FavoriteInfo.ModuleID              := Fields[f_moduleid].AsString;
              FavoriteInfo.Link                  := Fields[f_link].AsString;
              FavoriteInfo.Title                 := Fields[f_title].AsString;
              FavoriteInfo.Status                := Fields[f_status].AsString;
              FavoriteInfo.CurrentChapter        := Fields[f_currentchapter].AsString;
              FavoriteInfo.DownloadedChapterList := Fields[f_downloadedchapterlist].AsString;
              FavoriteInfo.SaveTo                := Fields[f_saveto].AsString;
              FavoriteInfo.DateAdded             := Fields[f_dateadded].AsDateTime;
              FavoriteInfo.DateLastChecked       := Fields[f_datelastchecked].AsDateTime;
              FavoriteInfo.DateLastUpdated       := Fields[f_datelastupdated].AsDateTime;
            end;
          FFavoritesDB.Table.Next;
        end;
      finally
        LeaveCriticalsection(CS_Favorites);
      end;
    finally
      FFavoritesDB.CloseTable;
    end;
end;

procedure TFavoriteManager.Backup;
var
  i: Integer;
begin
  if not FFavoritesDB.Connection.Connected then Exit;
  if Items.Count > 0 then
    try
      EnterCriticalsection(CS_Favorites);
      for i := 0 to Items.Count - 1 do
        with Items[i], FavoriteInfo do
          FFavoritesDB.InternalUpdate(
            i,
            FEnabled,
            ModuleID,
            Link,
            Title,
            Status,
            CurrentChapter,
            DownloadedChapterList,
            SaveTo,
            DateLastChecked,
            DateLastUpdated);
      FFavoritesDB.Commit;
    finally
      LeaveCriticalsection(CS_Favorites);
    end;
end;

procedure TFavoriteManager.AddToDownloadedChaptersList(const AWebsite,
  ALink: String; const AValue: TStrings);
var
  i: Integer;
begin
  if (Items.Count = 0) or (AWebsite = '') or (ALink = '') or (AValue.Count = 0) then Exit;
  try
    EnterCriticalsection(CS_Favorites);
    for i := 0 to Items.Count - 1 do
      with Items[i].FavoriteInfo do
        if SameText(AWebsite, ModuleID) and SameText(ALink, Link) then
        begin
          DownloadedChapterList := MergeCaseInsensitive([DownloadedChapterList, AValue.Text]);
          Break;
        end;
  finally
    LeaveCriticalsection(CS_Favorites);
  end;
end;

function CompareFavoriteContainer(const Item1, Item2: TFavoriteContainer): Integer;

  function GetStr(ARow: TFavoriteContainer): String;
  begin
    with ARow.FavoriteInfo do
      case ARow.Manager.SortColumn of
        1: Result := Title;
        2: Result := currentChapter;
        3: Result := Website;
        4: Result := SaveTo;
        else
          Result := '';
      end;
  end;

  function GetDateTime(ARow: TFavoriteContainer): TDateTime;
  begin
    with ARow.FavoriteInfo do
      case ARow.Manager.SortColumn of
        5: Result := DateAdded;
        6: Result := DateLastChecked;
        7: Result := DateLastUpdated;
        else
          Result := Now;
      end;
  end;

begin
  if (Item1.Manager.SortColumn >= 5) and (Item1.Manager.SortColumn <= 7) then
  begin
    if Item1.Manager.SortDirection then
      Result := CompareDateTime(GetDateTime(Item2), GetDateTime(Item1))
    else
      Result := CompareDateTime(GetDateTime(Item1), GetDateTime(Item2));
  end
  else
  begin
    if Item1.Manager.SortDirection then
      Result := NaturalCompareStr(GetStr(Item2), GetStr(Item1))
    else
      Result := NaturalCompareStr(GetStr(Item1), GetStr(Item2));
  end;
end;

procedure TFavoriteManager.Sort(const AColumn: Integer);
begin
  if Items.Count < 2 then Exit;
  EnterCriticalsection(CS_Favorites);
  try
    SortColumn := AColumn;
    Items.Sort(CompareFavoriteContainer);
  finally
    LeaveCriticalsection(CS_Favorites);
  end;
end;

procedure TFavoriteManager.Lock;
begin
  EnterCriticalsection(CS_Favorites);
end;

procedure TFavoriteManager.LockRelease;
begin
  LeaveCriticalsection(CS_Favorites);
end;

end.
