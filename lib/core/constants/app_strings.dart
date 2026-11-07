abstract class AppStrings {
  // アプリ共通
  static const appTitle = 'てくしぇあ';
  static const appTagline = '〜散歩の記録・発見・見守りをシェア〜';

  // ナビゲーション
  static const navHome = 'ホーム';
  static const navList = 'リスト';
  static const navRoute = '散歩ルート';
  static const navSettings = '設定';

  // ホーム画面
  static const startWalk = '散歩をはじめる';
  static const oneWay = '片道';

  // 散歩モード
  static const endWalk = '散歩を終了する';
  static const gpsAcquiring = 'GPS取得中...';
  static const gpsUnavailableError = 'GPS信号を取得できません';
  static const photoSpotTitle = '散歩スポット';
  static const photoTaken = '写真を撮影しました！行きたいリストに保存してください';
  static const endWalkConfirmMessage = '散歩を終了しますか？';
  static const endWalkConfirmButton = '終了する';
  static const takePhoto = '撮影する';
  static const saveToWantToGo = '現在地を\n行きたいリストに保存する';
  static const wantToGo = '行きたい！';
  static const recenterMap = '現在地に戻る';
  static const timerTurnaround = '折り返し';
  static const timerInactivity = '安否通知';
  static const timerReset = 'リセット';
  static const timerFinishedTitle = '散歩タイマー';
  static const timerFinishedMessage = '設定した時間になりました。';
  static const timerRoundTripNotificationTitle = '折り返しの時間です';
  static const timerRoundTripNotificationBody = 'そろそろ折り返しましょう！';
  static const gpsTimeoutTitle = 'GPS を取得できません';
  static const gpsTimeoutMessage =
      '60秒経っても、ルートの記録に使える精度の位置を取得できませんでした。\n散歩をやり直す場合はリトライしてください。';
  static const gpsTimeoutIndoorHint = '屋内では位置の精度が下がります。屋外や窓際へ移動すると記録が始まります。';
  static const gpsTimeoutPreciseOffHint =
      '「正確な位置情報」がオフになっています。設定でオンにすると記録できるようになります。';
  static const gpsOpenSettings = '設定を開く';
  static String gpsLowAccuracy(int meters) =>
      '位置の精度が低いため記録を待っています（誤差 約${meters}m）';
  static const gpsTimeoutRetry = 'やり直す';
  static const gpsTimeoutContinue = 'このまま続ける';
  static const safetyOk = '元気です';
  static const safetyConfirmTitle = '大丈夫ですか？';
  static const safetyConfirmBody = '動きがありません。\n応答がない場合、通知先・連携相手に知らせます。';
  static const safetyAlertSendingBody = '通知先・連携相手に知らせています…';
  static const safetyAlertSentBody = '通知先・連携相手に知らせました。\n元気な場合はボタンを押してください。';
  static const safetyAlertFailedBody =
      '通知先・連携相手に知らせることができませんでした。\n通信状況を確認してください。元気な場合はボタンを押してください。';
  static const smsSentNotificationTitle = '安否通知を送信しました';
  static const smsSentNotificationBody = '通知先・連携相手に安否通知を送りました。';
  static const walkForegroundNotificationTitle = 'てくしぇあ';
  static const walkForegroundNotificationBody = 'バックグラウンドでGPSを記録しています';
  static const walkReminderNotificationTitle = '散歩を続けていますか？';
  static String walkReminderNotificationBody(int hours) =>
      '散歩が$hours時間続いています。終了する場合はアプリを開いてください。';
  static const walkAutoEndWarningTitle = '散歩が自動終了します';
  static const walkAutoEndWarningBody = '散歩開始から7時間30分が経過しました。30分後に自動で散歩を終了します。';
  static const walkAutoEndNotificationTitle = '散歩を自動終了しました';
  static const walkAutoEndNotificationBody = '散歩開始から8時間が経過したため、自動で終了しました。';

  // 行きたい！ページ
  static const wantToGoPageTitle = '行きたい！';
  static const wantToGoSave = '行きたい！に保存';
  static const wantToGoConfirmMessage = '「行きたい！」に保存しますか？';
  static const saveButton = '保存する';
  static const cancelButton = 'キャンセル';
  static const closeButton = '閉じる';
  static const realtimeLocation = 'リアルタイム位置';
  static const addPhoto = '写真を追加';
  static const removePhoto = '写真を削除';
  static const titleHint = 'タイトルを設定する';

  // ニックネーム設定（表示名）
  static const displayNameTitle = 'ニックネームを設定';
  static const displayNameSubtitle = 'アプリ内で表示される名前を入力してください';
  static const displayNameSubmit = 'はじめる';
  static const displayNameError = 'エラーが発生しました';
  static const nicknameLabel = 'ニックネーム';
  static const nicknameHint = '例：やまだたろう';
  static const nicknameRequired = 'ニックネームを入力してください';

  // メールアドレス認証フォーム
  static const emailAuthPasswordLabel = 'パスワード（6文字以上）';
  static const emailAuthPasswordHint = '6文字以上';
  static const emailAuthPasswordAlphanumericError = 'パスワードは英字と数字を両方含めてください';
  static const emailAuthRegisteredDescription =
      'ご登録のメールアドレスに確認メールをお送りしました。\nメール内のリンクをクリックして確認を完了してから、ログインしてください。';
  static const emailSpamFolderWarning = 'メールが届かない場合は、迷惑メールフォルダをご確認ください。';
  static const emailAuthLoginButton = 'ログインへ';

  // メールアドレス確認
  static const emailVerificationPageTitle = 'メールをご確認ください';
  static const emailVerificationSentMessage = '確認メールを送りました';
  static const emailVerificationDescription =
      'にメールアドレス確認用のメールを送りました。\nメール内のリンクをタップして確認を完了してください。';
  static const emailVerificationResendButton = '確認メールを再送信';
  static const emailVerificationResendSuccess = '再送信しました';
  static const emailVerificationChecking = '確認しています...';

  // パスワード設定（メールリンクから遷移）
  static const passwordSetPageTitle = 'パスワードの設定';
  static const passwordSetDescription =
      '新しいパスワードを設定してください。\n英字と数字を両方含む6文字以上で設定してください。';
  static const passwordSetLabel = 'パスワード（6文字以上・英数字含む）';
  static const passwordSetConfirmLabel = 'パスワード（確認）';
  static const passwordSetButton = 'パスワードを設定する';
  static const passwordSetInvalidCode = 'このリンクは無効か期限切れです。パスワードリセットを再度お試しください。';
  static const passwordMismatch = 'パスワードが一致しません';

  // パスワードリセット
  static const passwordResetPageTitle = 'パスワードリセット';
  static const passwordResetDescription = '登録したメールアドレスにリセット用のメールを送信します。';
  static const passwordResetEmailLabel = 'メールアドレス';
  static const passwordResetSendButton = 'リセットメールを送信';
  static const passwordResetSuccessMessage = 'リセット用メールを送信しました。\nメールをご確認ください。';
  static const passwordResetLinkLabel = 'パスワードを忘れた方はこちら';

  // 共通
  static const noTitle = '（タイトルなし）';
  static const saved = '保存しました！';

  // カテゴリ
  static const categoryPark = '公園';
  static const categoryCafe = 'カフェ';
  static const categoryLunch = 'ランチ';
  static const categoryDinner = 'ディナー';
  static const categoryGoods = '雑貨屋';
  static const categoryOther = 'そのほか';

  // リストページ
  static const listWentTab = '行った！';
  static const spotListEmpty = 'スポットがありません';

  // スポット
  static const statusWantToGo = '行きたい';
  static const statusVisited = '行った';
  static const categoryChange = '行った！に変更';

  // 散歩ルートページ
  static const walkRoutePageTitle = '散歩ルート';
  static const savedRoutes = '保存済みのルートから選ぶ';
  static const selectedRoute = '選択中のルート';
  static const routeNameHint = '名前を設定する';
  static const saveRouteConfirmMessage = 'この散歩ルートを保存しますか？';
  static const saveRouteButton = 'このルートを保存する';
  static const routeDeleteConfirmMessage = '本当に消去しますか？';
  static const routeDeleteButton = '消去';
  static const fullscreenMapTooltip = 'マップを全画面表示';
  static const walkStartEndTime = '開始終了時間';
  static const walkDuration = '散歩時間';
  static const walkDistanceLabel = '距離';
  static const walkSpotCount = '行きたいスポット';
  static const viewDetails = '詳しく見る';

  // 履歴ページ
  static const historyPageTitle = '散歩履歴';
  static const historyEmpty = '散歩の記録がありません';
  static const historyLoadError = '履歴の読み込みに失敗しました';

  // スポット詳細
  static const spotDetailSaveButton = '上書き保存';
  static const spotDetailDeleteButton = '削除する';
  static const spotDetailMoveToWentButton = '行った！に保存';
  static const spotDetailMoveToWentConfirmLabel = '行った！';
  static const spotDetailSaveConfirmMessage = '上書き保存しますか？';
  static const spotDetailDeleteConfirmMessage = '削除しますか？';
  static const spotDetailMoveToWentConfirmMessage = '「行った！」に保存しますか？';
  static const spotDetailDeleted = '削除しました！';
  static const spotDetailMoveToWentDone = '行った！に保存しました！';

  // 設定画面
  static const settingsTitle = '設定';
  static const settingsTimerTitle = 'タイマー';
  static const settingsTimerSubtitle = 'タイマーで知らせる時間を設定';
  static const settingsTimerRoundTrip = '往復';
  static const settingsInactivityTitle = '安否確認';
  static const settingsInactivitySubtitle = '無動作感知システム';
  static const settingsInactivityContact = '通知先';
  static const settingsInactivityContactSet = '設定する';
  static String settingsInactivityPushNote(int linkedCount) =>
      '応答がないときは、連携相手（$linkedCount人）にプッシュ通知で知らせます。';
  static const settingsInactivityNoLinkNote =
      '連携相手がいないため、安否通知が届きません。下の「シェア」からリンクを送って連携してください。';
  static const settingsShareTitle = 'シェア';
  static const settingsShareSubtitle = '共有するアカウント設定';
  static const settingsShareRegistered = '登録済み';
  static const settingsShareNotRegistered = '未登録';
  static const settingsShareLinkLabel = '共有リンク';
  static const settingsShareLinkCopy = 'コピー';
  static const settingsShareViaApp = 'アプリで共有';
  static const settingsShareContent = '共有する内容';
  static const settingsShareWantToGo = '行きたい！リスト';
  static const settingsShareVisited = '行った！リスト';
  static const settingsShareSendButton = 'リンクを送る';
  static const settingsShareSaveButton = '内容保存';
  static const settingsShareDeleteConfirmMessage = '本当に消去してよろしいですか？';
  static const settingsShareDeleteConfirmButton = '消去する';
  static const pickerDone = '完了';
  static const minuteSuffix = '分';
  static const switchOn = 'ON';
  static const switchOff = 'OFF';
  static const settingsPhoneSelectTitle = '電話番号を選択';
  static const settingsPhoneRegisterButton = 'この番号を登録する';
  static const settingsPhoneConfirmMessage = '安否確認先の電話番号に\n登録しますか？';
  static const settingsPhoneRegisterConfirm = '登録する';
  static const settingsPhoneRegisteredMessage = '登録しました！';
  static const settingsPhoneNameLabel = '名前';
  static const settingsPhoneNameHint = '例：あかり（娘）';
  static const settingsPhoneNameRequired = '名前を入力してください';
  static const settingsPhoneNumberLabel = '電話番号';
  static const settingsPhoneNumberHint = '例：080-0000-0000';
  static const settingsPhoneNumberRequired = '電話番号を入力してください';
  static const settingsPhoneSaveButton = '上書き保存';
  static const settingsPhoneDeleteButton = '登録を削除する';
  static const settingsPhoneDeleteConfirmMessage = '通知先の登録を削除しますか？';
  static const settingsPhoneDeleteConfirmButton = '削除する';
  static const settingsPhoneAddButton = '追加する';

  // アカウント管理
  static const settingsAccountTitle = 'アカウント';
  static const settingsLogout = 'ログアウト';
  static const settingsDeleteAccount = 'アカウントを消去';
  static const settingsLogoutConfirmMessage = 'ログアウトしますか？';
  static const settingsDeleteAccountConfirmMessage =
      'アカウントを消去しますか？\nこの操作は取り消せません。';
  static const settingsLogoutConfirmButton = 'ログアウト';
  static const settingsDeleteAccountConfirmButton = '消去する';
  static const settingsReauthTitle = 'パスワードの確認';
  static const settingsReauthMessage = '安全のため、アカウントを消去する前にもう一度パスワードを入力してください。';
  static const settingsReauthPasswordLabel = 'パスワード';
  static const settingsReauthConfirmButton = '確認して消去';
  static const settingsDeleteAccountError = 'アカウントの消去に失敗しました。時間をおいて再度お試しください';
  static const settingsPrivacyPolicy = 'プライバシーポリシー';
  static const privacyPolicyUrl = 'https://tekushare.web.app/privacy.html';

  // アカウント連携（シェアカード内）
  static const accountLinkInviteDescription =
      'リンクを送って、相手が開くと連携できます。\nアプリを両方の端末に入れておく必要があります。';
  static const accountLinkGenerateButton = 'リンクを作成';
  static const accountLinkGenerateError = 'リンクの作成に失敗しました';
  static const accountLinkUnlinkError = '連携の解除に失敗しました';
  static const accountLinkCopied = 'リンクをコピーしました';
  static const accountLinkEditTooltip = '連携済みアカウントを編集';
  static const accountLinkDoneTooltip = '編集を完了';
  static const accountLinkUnlinkTooltip = '連携を解除';
  static const accountLinkViewSpots = 'スポットを見る';
  static const linkedAccountSpotsEmpty = '共有されたスポットがありません';
  static const linkedAccountRoutesEmpty = '共有されたルートがありません';
  static const linkedAccountLoadError = '読み込みに失敗しました';
  static const linkedSpotLabelTitle = 'タイトル';
  static const linkedSpotLabelTag = 'タグ';
  static const linkedSpotLabelPhoto = '写真';

  // SNSシェア
  static const shareInviteText = 'てくしぇあで散歩記録をシェアしませんか？';
  static const shareLinkRequired = 'リンクを先に作成してください';
  static const shareInstagramCopied = 'リンクをコピーしました。Instagramに貼り付けてください';
  static const shareError = 'シェアに失敗しました';

  // 招待承認画面
  static const acceptInviteTitle = 'アカウント連携';
  static const acceptInviteMessage = 'さんと連携しますか？';
  static const acceptInviteDescription = '連携すると、行きたい！リストや行った！リストを共有できるようになります。';
  static const acceptInviteConfirmButton = '連携する';
  static const acceptInviteSuccessMessage = '連携しました！';
  static const acceptInviteInvalidMessage = 'この招待リンクは無効か、期限が切れています。';
  static const acceptInviteSelfMessage = '自分自身のリンクは使用できません。';
  static const acceptInviteAlreadyLinkedMessage = 'すでに連携済みです。';
  static const acceptInviteErrorMessage = '連携に失敗しました。もう一度お試しください。';
  static const operationError = 'エラーが発生しました。もう一度お試しください。';
}
