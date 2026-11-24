# Deep Review

Ứng dụng macOS để review và nâng cấp tài liệu theo nhiều lượt, luân phiên giữa Claude và ChatGPT.

Repo này chỉ chứa trình cài đặt và các bản phát hành (tệp `DeepReview.app.zip` trong mục Releases).

## Cài đặt

```bash
curl -fsSL https://raw.githubusercontent.com/haiz/deep-review-releases/main/install.sh | bash
```

Trình cài đặt kiểm tra điều kiện, tải bản mới nhất, cài vào `/Applications/DeepReview.app`, rồi in lệnh để mở ứng dụng:

```bash
open /Applications/DeepReview.app
```

Chạy lại cùng lệnh để cập nhật. Nếu Deep Review đang chạy, trình cài đặt sẽ hỏi trước khi thoát nó.

## Yêu cầu

- macOS 15 trở lên (Apple Silicon hoặc Intel).
- Node 22 trở lên. Cài bằng `brew install node`, hoặc dùng nvm, fnm, volta.
- Google Chrome trong `/Applications` hoặc `~/Applications`: https://www.google.com/chrome/
- claude-dashboard, đã đăng nhập ít nhất một tài khoản Claude (khuyến nghị): thiếu thì các bước ChatGPT vẫn chạy, nhưng các bước dùng Claude sẽ báo lỗi.

## Lưu ý

Ứng dụng chỉ được ký ad-hoc. Trình cài đặt đã gỡ thuộc tính cách ly, nhưng nếu macOS vẫn chặn ở lần mở đầu tiên, vào System Settings > Privacy & Security > Open Anyway.
