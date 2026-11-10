<p align="center">
  <img src="docs/images/app-icon.png" width="132" alt="Biểu tượng ứng dụng 3106">
</p>

<h1 align="center">3106</h1>

<p align="center">
  Kho nội dung và trình quản lý Patch, dữ liệu ứng dụng, Dialer và hình nền dành cho iOS.
</p>

<p align="center">
  <img alt="Phiên bản" src="https://img.shields.io/badge/phiên%20bản-3.0-E6753A?style=flat-square">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-17.0–18.7.1%20%7C%2026.0–26.7.2%20%7C%2027.0–27.2-222222?style=flat-square">
  <img alt="Ngôn ngữ" src="https://img.shields.io/badge/ngôn%20ngữ-English%20%7C%20Tiếng%20Việt%20%7C%20简体中文-E6753A?style=flat-square">
</p>

<p align="center"><a href="README.md">English</a> · <a href="docs/PATCH_GUIDE.vi.md">Hướng dẫn Patch</a> · <a href="#giấy-phép">Giấy phép</a></p>

> [!WARNING]
> 3106 là phần mềm nghiên cứu để quản lý thiết bị cá nhân. Chỉ sử dụng trên thiết bị và dữ liệu thuộc quyền sở hữu của bạn, đồng thời luôn sao lưu trước khi thay đổi dữ liệu ứng dụng.

## Giao diện

<p align="center">
  <img src="docs/images/home-2.0.png" width="245" alt="Trang chủ 3106 2.0">
  &nbsp;
  <img src="docs/images/sources-2.0.png" width="245" alt="Nguồn nội dung 3106 2.0">
  &nbsp;
  <img src="docs/images/installed-2.0.png" width="245" alt="Nội dung đã cài trong 3106 2.0">
</p>

## Có gì mới trong 3.0

- **iOS 27 qua `worse_query`** — 3106 thay `bad_query` đã lỗi thời trên iOS 26.7–26.7.2 và 27.0–27.2 bằng `worse_query` của Taj C (forcequitOS). Không dùng kernel exploit trên các bản này.
- **Backend kết hợp** — iOS 26.0–26.6.1 vẫn dùng `bad_query`; iOS 26.7+ và 27.x tự chọn `worse_query`.
- **Cần App Group** — `worse_query` yêu cầu App Group entitlement. AltStore, SideStore và Sideloadly tự tạo bằng Apple ID miễn phí; profile wildcard không mang được.
- **Đổi tên thành 3106** — bundle ID `com.qingtang.3106`, URL scheme `threeoneossix`, gói Patch mới dùng `.3106`; gói `.3105` cũ vẫn nhập được và vẫn giải mã với magic `3105PATCH` không đổi.

## Có gì mới trong 2.0

- **Kho nội dung mới** — khám phá Patch, hình nền, Dialer và tính năng 3106 từ Dành cho bạn, Mới cập nhật hoặc từng nguồn; tiến trình tải và kết quả cài đặt được hiển thị rõ ràng.
- **Đã cài gọn gàng hơn** — mọi nội dung đã tải được quản lý tại một nơi, có tên, biểu tượng và loại nội dung để dễ nhận biết. 3106 cũng thông báo khi gói đã cài có bản cập nhật.
- **Patch linh hoạt hơn** — một Patch có thể dùng cho nhiều ứng dụng và App Group, tự tìm dữ liệu phù hợp trên từng máy và vẫn áp dụng được những phần đang có trên thiết bị.
- **Tùy chỉnh Patch** — tác giả có thể cho người dùng nhập nội dung, bật công tắc hoặc chọn giá trị trước khi áp dụng. Patch hỗ trợ thay file, chỉnh sửa plist/JSON và mật khẩu tùy chọn.
- **Khôi phục an toàn hơn** — cải thiện sao lưu, đặt lại, khôi phục và xóa Patch đang hoạt động; kết quả mỗi thao tác được thông báo rõ ràng hơn.
- **Dialer** — hỗ trợ gói `.3105pass`, tự nhận dạng kiểu phím sáng, tối và chữ đậm theo dữ liệu có trên thiết bị.
- **Hình nền từ kho** — tải và quản lý gói `.tendies` ngay trong ứng dụng, xem ảnh trong mô tả và xóa nội dung đã cài tại mục Đã cài.
- **Trình quản lý Tệp mới** — tách rõ Workspace 3106, Application và App Group; bổ sung tệp ẩn, thẻ Tệp, yêu thích, thông tin file và trình chỉnh sửa plist đơn giản.
- **Tính năng 3106** — Dọn dẹp trở thành tính năng có thể cài hoặc gỡ; Footnote màn hình khóa và Supervised có trên các bản iOS 27 được hỗ trợ.
- **Giao diện và phản hồi** — thiết kế lại trang chủ, nguồn, chi tiết gói và Đã cài; trạng thái tương thích, tải xuống, cài đặt và lỗi đều dễ hiểu hơn.

So với 1.1.1, bản 2.0 chuyển 3106 từ một bộ công cụ riêng lẻ thành một nơi thống nhất để tìm, cài đặt và quản lý nội dung.

## Tính năng chính

- Khám phá và cài nội dung trực tiếp từ nhiều nguồn trong Kho 3106.
- Quản lý Patch, hình nền, Dialer và tính năng 3106 trong mục **Đã cài**.
- Duyệt dữ liệu theo tên ứng dụng, **bundle identifier** hoặc App Group.
- Trình quản lý tệp có tìm kiếm, xem trước, chia sẻ, nhập nhiều tệp, sao chép, di chuyển, đổi tên, xóa, nén/giải nén ZIP, thẻ Tệp và yêu thích.
- Tạo và nhập Patch `.3106` hỗ trợ nhiều ứng dụng, App Group, tùy chỉnh trước khi áp dụng và mật khẩu tùy chọn.
- Cài Dialer `.3105pass`, hình nền `.tendies` và các tính năng do 3106 cung cấp.
- Sao lưu và khôi phục file gốc khi áp dụng Patch; chỉ xóa dữ liệu tạm đã xác định khi sử dụng Dọn dẹp.
- 3106 không cài jailbreak, bootstrap hay daemon thường trú và không inject mã vào ứng dụng bên thứ ba. Do ứng dụng vẫn dùng khai thác thiết bị và có thể sửa dữ liệu app, không thể bảo đảm vượt qua mọi cơ chế kiểm tra tính toàn vẹn hoặc phát hiện jailbreak.
- Hỗ trợ tiếng Anh, tiếng Việt và tiếng Trung giản thể.

## Phiên bản iOS đã xác minh

| Hệ thống | Phiên bản | Backend |
| --- | --- | --- |
| iOS 17 | 17.0–17.7.x | kernel exploit |
| iOS 18 | 18.0–18.7.1 | kernel exploit |
| iOS 26 | 26.0–26.6.1 | `bad_query` |
| iOS 26 | 26.7–26.7.2 | `worse_query` |
| iOS 27 | 27.0–27.2 | `worse_query` |
| iOS 27.3 beta 1 | thử nghiệm | `worse_query` (chưa xác minh) |

## Lưu ý cài đặt

- **iOS 26.7+ và iOS 27 cần App Group.** Ký bằng AltStore, SideStore hoặc Sideloadly với Apple ID (miễn phí hoặc trả phí) — chúng tự tạo App Group. Với Feather/ESign hoặc chứng chỉ, profile phải là App ID rõ ràng có App Groups; profile wildcard sẽ lỗi entitlement.
- **Bundle ID:** `com.qingtang.3106`. ID giả `com.apple.mobile.MobileHouseArrest` gắn với luồng MHA-C2 và không thể đăng ký App Group; 3106 không dùng luồng đó trên iOS 26/27.
- **iOS 17/18:** chuỗi kernel exploit không đổi; App Group không bắt buộc nhưng không gây hại.
- Cây mã nguồn không chứa chứng chỉ, provisioning profile, ứng dụng đã ký hoặc IPA; phần Release có thể cung cấp IPA unsigned.

## Tác giả và ghi công

3106 là bản fork của [3105](https://github.com/YangJiiii/3105), được phát triển và thiết kế bởi [YangJiii](https://x.com/duongduong0908). `worse_query` do Taj C (forcequitOS) phát hành; phần an toàn sản phẩm được tham khảo từ WQ Files của Christoph Kolbicz. Xem [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) để biết đầy đủ.

## Giấy phép

Phần mã gốc của 3106 được phát hành theo [GNU General Public License v3.0](LICENSE). Thành phần của bên thứ ba vẫn tuân theo bản quyền và điều khoản của dự án nguồn tương ứng; xem [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
