import SwiftUI
import Combine

// MARK: - 下部ナビゲーションバー

/**
 画面下に表示するカスタムタブバー。

 入力、カレンダー、分析、予算、その他の5つの画面を切り替える。

 MainView から selectedTab を Binding で受け取り、
 ボタンが押されたら selectedTab を変更する。

 バーの高さ・色・余白・アイコンサイズなどは、
 上の変数を変更するだけで調整できる。
 */
struct BottomNavigationView: View {
    /**
     現在選択されているタブ。

     MainView の selectedTab とつながっている。
     ここを変更すると、MainView 側の表示画面も切り替わる。
     */
    @Binding var selectedTab: AppTab

    /**
     選択中タブをもう一度タップした時に呼ばれる。

     MainView 側で該当タブの resetTrigger をインクリメントする。
     */
    var onReselectTab: (AppTab) -> Void = { _ in }

    @AppStorage(AppColors.themeColorStorageKey)
    private var themeHex: String = AppColors.defaultThemeHex

    // MARK: - 色設定

    /**
     選択中タブの色。
     */
    private var selectedColor: Color { AppColors.main }

    /**
     未選択タブの色。
     */
    private let unselectedColor = Color.gray

    /**
     バー本体の背景色。
     */
    private let barBackgroundColor = Color.white

    /**
     バーの枠線色。
     */
    private let barBorderColor = Color.gray.opacity(0.25)

    /**
     バーの影の色。
     影を消したい場合は opacity を 0 にする。
     */
    private let barShadowColor = Color.black.opacity(0.06)

    // MARK: - バー全体のサイズ・位置設定

    /**
     バー全体の高さ。

     大きくするとカプセル全体が縦に大きくなる。
     */
    private let barHeight: CGFloat = 78

    /**
     バー全体の左右余白。

     大きくするとバーが細くなる。
     小さくするとバーが横に広がる。
     */
    private let barOuterHorizontalPadding: CGFloat = 20

    /**
     バーを画面下からどれだけ上げるか。

     大きくするとバーが上に上がる。
     小さくすると下に下がる。
     */
    private let barBottomPadding: CGFloat = -10

    /**
     バーの角丸。

     カプセル型にしたい場合は barHeight の半分くらいにする。
     */
    private let barCornerRadius: CGFloat = 39

    /**
     バーの枠線の太さ。
     */
    private let barBorderWidth: CGFloat = 1

    /**
     バーの影のぼかし量。
     */
    private let barShadowRadius: CGFloat = 4

    /**
     バーの影のY方向位置。
     */
    private let barShadowYOffset: CGFloat = 2

    // MARK: - バー内側の余白設定

    /**
     バー内側の左右余白。

     大きくすると各タブが中央に寄る。
     */
    private let barInnerHorizontalPadding: CGFloat = 18

    /**
     バー内側の上下余白。

     barHeight を使って高さ管理する場合は、
     ここは小さめでOK。
     */
    private let barInnerVerticalPadding: CGFloat = 0

    /**
     タブ同士の横方向の間隔。
     */
    private let tabSpacing: CGFloat = 0

    // MARK: - タブ1個分のサイズ設定

    /**
     タブ1個分の高さ。

     バーの中に入るアイコン+文字の領域。
     */
    private let tabItemHeight: CGFloat = 58

    /**
     アイコンと文字の間隔。
     */
    private let iconTextSpacing: CGFloat = 4

    /**
     アイコンのサイズ。
     */
    private let iconFontSize: CGFloat = 23

    // タイトル文字のフォントは AppFonts.navigationTitle / navigationTitleSelected を使用（tabItem 内）

    /**
     タブ全体のY方向位置調整。

     マイナスにするとアイコンと文字が上へ動く。
     プラスにすると下へ動く。
     */
    private let tabItemYOffset: CGFloat = 0

    /**
     アイコンだけのY方向位置調整。
     */
    private let iconYOffset: CGFloat = 0

    /**
     文字だけのY方向位置調整。
     */
    private let titleYOffset: CGFloat = 0

    // MARK: - タブ選択処理

    /**
     すでに選択中のタブが押された場合は onReselectTab を呼び、
     別のタブが押された場合は selectedTab を切り替える。
     */
    private func selectTab(_ tab: AppTab) {
        if selectedTab == tab {
            onReselectTab(tab)
        } else {
            selectedTab = tab
        }
    }

    // MARK: - 画面本体

    var body: some View {
        HStack(spacing: tabSpacing) {
            Button {
                selectTab(.input)
            } label: {
                tabItem(
                    icon: "square.and.pencil",
                    title: "入力",
                    isSelected: selectedTab == .input
                )
            }

            Button {
                selectTab(.calendar)
            } label: {
                tabItem(
                    icon: "calendar",
                    title: "カレンダー",
                    isSelected: selectedTab == .calendar
                )
            }

            Button {
                selectTab(.analysis)
            } label: {
                tabItem(
                    icon: "chart.bar.xaxis",
                    title: "分析",
                    isSelected: selectedTab == .analysis
                )
            }

            Button {
                selectTab(.budget)
            } label: {
                tabItem(
                    icon: "wallet.pass",
                    title: "予算",
                    isSelected: selectedTab == .budget
                )
            }

            Button {
                selectTab(.other)
            } label: {
                tabItem(
                    icon: "gearshape",
                    title: "設定",
                    isSelected: selectedTab == .other
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, barInnerHorizontalPadding)
        .padding(.vertical, barInnerVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
        .background(
            RoundedRectangle(cornerRadius: barCornerRadius)
                .fill(barBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: barCornerRadius)
                .stroke(barBorderColor, lineWidth: barBorderWidth)
        )
        .shadow(
            color: barShadowColor,
            radius: barShadowRadius,
            x: 0,
            y: barShadowYOffset
        )
        .padding(.horizontal, barOuterHorizontalPadding)
        .padding(.bottom, barBottomPadding)
    }

    // MARK: - タブ1個分の見た目

    /**
     タブボタン1個分の見た目。

     icon:
     - SF Symbols の名前

     title:
     - タブ下に表示する文字

     isSelected:
     - 現在選択中なら true
     - 未選択なら false
     */
    private func tabItem(
        icon: String,
        title: String,
        isSelected: Bool
    ) -> some View {
        VStack(spacing: iconTextSpacing) {
            Image(systemName: icon)
                .font(.system(size: iconFontSize, weight: .regular))
                .offset(y: iconYOffset)

            Text(title)
                .font(isSelected ? AppFonts.navigationTitleSelected : AppFonts.navigationTitle)
                .offset(y: titleYOffset)
        }
        .foregroundStyle(isSelected ? selectedColor : unselectedColor)
        .frame(maxWidth: .infinity)
        .frame(height: tabItemHeight)
        .offset(y: tabItemYOffset)
    }
}
