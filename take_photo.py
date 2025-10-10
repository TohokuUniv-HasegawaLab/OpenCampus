import cv2
import os

# デスクトップのパスを取得
desktop_path = os.path.join(os.path.expanduser("~"), "Desktop/OpenCampas")

# 保存フォルダ名（Desktop内）
folder_name = "picture"
save_dir = os.path.join(desktop_path, folder_name)

# フォルダがなければ作成
os.makedirs(save_dir, exist_ok=True)

# カメラを起動（通常は0。外付けカメラなら1など）
cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("カメラが起動できませんでした。")
    exit()

print("カメラ起動中。スペースキーで写真を撮影、Escで終了。")

while True:
    ret, frame = cap.read()
    if not ret:
        print("カメラからフレームを取得できません。")
        break

    # 映像を表示
    cv2.imshow("Camera", frame)

    key = cv2.waitKey(1)

    # スペースキーで保存
    if key == 32:  # Space key)
        filename = f"photo_send.jpg"
        filepath = os.path.join(save_dir, filename)

        # 画像を保存
        cv2.imwrite(filepath, frame)
        print(f"写真を保存しました: {filepath}")

    # ESCキーで終了
    elif key == 27:
        break

# カメラとウィンドウを解放
cap.release()
cv2.destroyAllWindows()