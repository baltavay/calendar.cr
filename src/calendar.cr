require "ori"
require "json"

THEME_PATH    = Path.home / ".config/omarchy/current/theme/colors.toml"
SETTINGS_DIR  = Path.home / ".config/calendar"
SETTINGS_PATH = SETTINGS_DIR / "settings.json"

MONTH_NAMES = {
  1 => "January", 2 => "February", 3 => "March",
  4 => "April", 5 => "May", 6 => "June",
  7 => "July", 8 => "August", 9 => "September",
  10 => "October", 11 => "November", 12 => "December",
}

DAY_NAMES_SUN = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
DAY_NAMES_MON = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

DIGITS = [
  [[1, 1, 1], [1, 0, 1], [1, 0, 1], [1, 0, 1], [1, 1, 1]],
  [[0, 1, 0], [1, 1, 0], [0, 1, 0], [0, 1, 0], [1, 1, 1]],
  [[1, 1, 1], [0, 0, 1], [1, 1, 1], [1, 0, 0], [1, 1, 1]],
  [[1, 1, 1], [0, 0, 1], [1, 1, 1], [0, 0, 1], [1, 1, 1]],
  [[1, 0, 1], [1, 0, 1], [1, 1, 1], [0, 0, 1], [0, 0, 1]],
  [[1, 1, 1], [1, 0, 0], [1, 1, 1], [0, 0, 1], [1, 1, 1]],
  [[1, 1, 1], [1, 0, 0], [1, 1, 1], [1, 0, 1], [1, 1, 1]],
  [[1, 1, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1]],
  [[1, 1, 1], [1, 0, 1], [1, 1, 1], [1, 0, 1], [1, 1, 1]],
  [[1, 1, 1], [1, 0, 1], [1, 1, 1], [0, 0, 1], [1, 1, 1]],
]

FLASH_DURATION =  8
TOAST_DURATION = 90
TICK_INTERVAL  = 33.milliseconds

class CalendarNode < Ori::Node
  @year : Int32
  @month : Int32
  @cursor_day : Int32
  @today : Time
  @monday_first : Bool
  @theme : Hash(String, String)
  @theme_mtime : Time?
  @flash_frames : Int32
  @toast_frames : Int32
  @toast_text : String

  def initialize(
    @year : Int32,
    @month : Int32,
    @cursor_day : Int32,
    @today : Time,
    @monday_first : Bool,
    @theme : Hash(String, String),
    @theme_mtime : Time?,
    @flash_frames : Int32,
    @toast_frames : Int32,
    @toast_text : String,
    style : Ori::S = Ori::S.none,
  )
    super(style)
  end

  def content_height : Int32
    1
  end

  def content_width : Int32
    1
  end

  def focusable? : Bool
    true
  end

  def render(io : IO) : Nil
  end

  def render_screen(screen : Ori::Screen) : Nil
    r = @rect
    return if r.w <= 0 || r.h <= 0
    bg = t("background", "#000000")
    w = r.w
    h = r.h
    x0 = r.x
    y0 = r.y

    return if h < 5

    help_y = y0 + h - 1
    toast_y = y0 + h - 2

    cell_w = w // 7
    grid_w = cell_w * 7
    offset_x = x0 + (w - grid_w) // 2

    draw_title_row(screen, x0, y0, w, bg)
    draw_empty_row(screen, x0, y0 + 1, w, bg)
    draw_day_header(screen, offset_x, y0 + 2, grid_w, cell_w, bg)
    draw_empty_row(screen, x0, y0 + 3, w, bg)

    grid_top = y0 + 4
    grid_bottom = toast_y - 1
    grid_h = {grid_bottom - grid_top + 1, 0}.max

    nw = week_count
    sw = start_wday
    dim = days_in_current_month

    cell_h = grid_h > 0 && nw > 0 ? grid_h // nw : 1
    scale = calc_scale(cell_w, {cell_h, 1}.max)
    digit_h = scale < 1 ? 1 : 5 * scale
    pad_top = {cell_h - digit_h, 0}.max // 2
    pad_bottom = {cell_h - digit_h - pad_top, 0}.max

    (grid_top..grid_bottom).each do |ey|
      draw_empty_row(screen, x0, ey, w, bg)
    end

    offset = sw
    week_data = Array(Array(Tuple(String, String?, String?))).new(7) { [] of Tuple(String, String?, String?) }

    (1..dim).each do |day|
      rendered = render_number(day, scale, cell_w)
      today_flag = is_today(day)
      selected = day == @cursor_day

      sfg : String? = nil
      sbg : String? = nil
      if today_flag && selected
        sfg = bg; sbg = t("color11", "#ffff00")
      elsif today_flag
        sfg = bg; sbg = t("color6", "#00ffff")
      elsif selected
        sfg = t("color7", "#ffffff"); sbg = t("color5", "#ff00ff")
      else
        sfg = t("foreground", "#ffffff")
      end

      styled = rendered.map { |row| {row, sfg.as(String?), sbg.as(String?)} }
      week_data[offset] = styled
      offset += 1
      if offset > 6
        grid_top = emit_week(screen, offset_x, grid_top, grid_w, cell_w, week_data, digit_h, pad_top, pad_bottom, bg, grid_bottom)
        week_data = Array(Array(Tuple(String, String?, String?))).new(7) { [] of Tuple(String, String?, String?) }
        offset = 0
      end
    end

    if week_data.any?(&.any?)
      emit_week(screen, offset_x, grid_top, grid_w, cell_w, week_data, digit_h, pad_top, pad_bottom, bg, grid_bottom)
    end

    if @toast_frames > 0
      alpha = @toast_frames.to_f / TOAST_DURATION
      tr, tg, tb = hex_to_rgb(t("accent", "#888888"))
      br, bg_i, bb = hex_to_rgb(bg)
      cr = (br + (tr - br) * alpha).to_i.clamp(0, 255)
      cg = (bg_i + (tg - bg_i) * alpha).to_i.clamp(0, 255)
      cb = (bb + (tb - bb) * alpha).to_i.clamp(0, 255)
      toast_fg = "##{cr.to_s(16).rjust(2, '0')}#{cg.to_s(16).rjust(2, '0')}#{cb.to_s(16).rjust(2, '0')}"
      draw_centered_row(screen, x0, toast_y, w, " #{@toast_text} ", toast_fg, bg)
    else
      draw_empty_row(screen, x0, toast_y, w, bg)
    end

    draw_centered_row(screen, x0, help_y, w, "hjkl: move  H/L: month  J/K: year  m: monday first  t: today  q: quit", t("color8", "#666666"), bg)
  end

  private def draw_title_row(screen : Ori::Screen, x : Int32, y : Int32, w : Int32, bg : String) : Int32
    title = "#{MONTH_NAMES[@month]} #{@year}"
    fc = flash_color
    pad = (w - title.size) // 2
    cx = x
    pad.times do
      screen.put(cx, y, ' ', fg: fc, bg: bg, bold: true); cx += 1
    end
    title.each_char do |ch|
      screen.put(cx, y, ch, fg: fc, bg: bg, bold: true); cx += 1
    end
    while cx < x + w
      screen.put(cx, y, ' ', fg: fc, bg: bg, bold: true); cx += 1
    end
    y + 1
  end

  private def draw_day_header(screen : Ori::Screen, x : Int32, y : Int32, w : Int32, cell_w : Int32, bg : String) : Int32
    names = @monday_first ? DAY_NAMES_MON : DAY_NAMES_SUN
    hfg = t("color11", "#ffff00")
    cx = x
    7.times do |col|
      name = names[col]
      left = (cell_w - name.size) // 2
      right = cell_w - name.size - left
      left.times do
        screen.put(cx, y, ' ', fg: hfg, bg: bg, bold: true); cx += 1
      end
      name.each_char do |ch|
        screen.put(cx, y, ch, fg: hfg, bg: bg, bold: true); cx += 1
      end
      right.times do
        screen.put(cx, y, ' ', fg: hfg, bg: bg, bold: true); cx += 1
      end
    end
    y + 1
  end

  private def draw_empty_row(screen : Ori::Screen, x : Int32, y : Int32, w : Int32, bg : String) : Int32
    w.times { |i| screen.put(x + i, y, ' ', bg: bg) }
    y + 1
  end

  private def draw_centered_row(screen : Ori::Screen, x : Int32, y : Int32, w : Int32, text : String, fg : String, bg : String) : Int32
    pad = {(w - text.size) // 2, 0}.max
    cx = x
    pad.times do
      screen.put(cx, y, ' ', fg: fg, bg: bg); cx += 1
    end
    text.each_char do |ch|
      screen.put(cx, y, ch, fg: fg, bg: bg); cx += 1
    end
    while cx < x + w
      screen.put(cx, y, ' ', fg: fg, bg: bg); cx += 1
    end
    y + 1
  end

  private def emit_week(
    screen : Ori::Screen,
    x : Int32, y : Int32, w : Int32, cell_w : Int32,
    week : Array(Array(Tuple(String, String?, String?))),
    digit_h : Int32, pad_top : Int32, pad_bottom : Int32,
    bg : String, max_y : Int32,
  ) : Int32
    bg_val = bg
    ry = y
    pad_top.times do
      break if ry > max_y
      draw_empty_row(screen, x, ry, w, bg_val); ry += 1
    end
    digit_h.times do |r|
      break if ry > max_y
      cx = x
      7.times do |col|
        rendered = week[col]?
        if rendered && rendered.size > r
          row_text, sfg, sbg = rendered[r]
          row_text.each_char do |ch|
            break if cx >= x + w
            screen.put(cx, ry, ch, fg: sfg, bg: sbg || bg_val, bold: !sfg.nil?)
            cx += 1
          end
        else
          cell_w.times do
            break if cx >= x + w
            screen.put(cx, ry, ' ', bg: bg_val); cx += 1
          end
        end
      end
      while cx < x + w
        screen.put(cx, ry, ' ', bg: bg_val); cx += 1
      end
      ry += 1
    end
    pad_bottom.times do
      break if ry > max_y
      draw_empty_row(screen, x, ry, w, bg_val); ry += 1
    end
    ry
  end

  private def render_number(n : Int32, scale : Int32, cell_w : Int32) : Array(String)
    return [n.to_s.center(cell_w)] if scale < 1

    chars = n.to_s.chars.map { |c| DIGITS[c.to_i] }
    digit_h = 5 * scale
    rows = Array(String).new(digit_h) { "" }

    chars.each_with_index do |pat, di|
      if di > 0
        rows.each_with_index do |_, r|
          rows[r] += " " * scale
        end
      end
      pat.each_with_index do |row, pr|
        scale.times do |sr|
          ri = pr * scale + sr
          row.each do |px|
            rows[ri] += (px == 1 ? "█" : " ") * scale
          end
        end
      end
    end

    rows.map do |row|
      pad = cell_w - row.size
      left = pad // 2
      right = pad - left
      " " * left + row + " " * right
    end
  end

  private def grid_wday(day_of_week_value : Int32) : Int32
    wday = day_of_week_value % 7
    @monday_first ? (wday + 6) % 7 : wday
  end

  private def start_wday : Int32
    grid_wday(Time.utc(@year, @month, 1).day_of_week.value)
  end

  private def days_in_current_month : Int32
    ny = @month == 12 ? @year + 1 : @year
    nm = @month == 12 ? 1 : @month + 1
    (Time.utc(ny, nm, 1) - Time.utc(@year, @month, 1)).days.to_i
  end

  private def week_count : Int32
    (start_wday + days_in_current_month + 6) // 7
  end

  private def is_today(day : Int32) : Bool
    @today.year == @year && @today.month == @month && @today.day == day
  end

  private def calc_scale(cell_w : Int32, cell_h : Int32) : Int32
    sw = (cell_w - 2) // 7
    sh = (cell_h - 2) // 5
    s = {sw, sh}.min
    s < 1 ? 0 : s
  end

  private def t(key : String, fallback : String) : String
    @theme[key]? || fallback
  end

  private def flash_color : String
    return t("accent", "#888888") if @flash_frames <= 0
    frac = @flash_frames.to_f / FLASH_DURATION
    r1, g1, b1 = hex_to_rgb(t("accent", "#888888"))
    r2, g2, b2 = 255, 255, 255
    r = (r1 + (r2 - r1) * frac).to_i.clamp(0, 255)
    g = (g1 + (g2 - g1) * frac).to_i.clamp(0, 255)
    b = (b1 + (b2 - b1) * frac).to_i.clamp(0, 255)
    "##{r.to_s(16).rjust(2, '0')}#{g.to_s(16).rjust(2, '0')}#{b.to_s(16).rjust(2, '0')}"
  end

  private def hex_to_rgb(hex : String) : {Int32, Int32, Int32}
    h = hex.lchop('#')
    return {0, 0, 0} if h.size < 6
    {h[0..1].to_i(16), h[2..3].to_i(16), h[4..5].to_i(16)}
  end
end

class CalendarApp < Ori::App
  @year : Int32
  @month : Int32
  @cursor_day : Int32
  @today : Time
  @theme : Hash(String, String)
  @theme_mtime : Time?
  @flash_frames : Int32
  @toast_frames : Int32
  @toast_text : String
  @monday_first : Bool

  def initialize
    super
    @today = Time.utc
    @year = @today.year
    @month = @today.month
    @cursor_day = @today.day
    @theme = {} of String => String
    @theme_mtime = nil
    @flash_frames = 0
    @toast_frames = 0
    @toast_text = ""
    @monday_first = load_settings
    reload_theme_if_changed
  end

  def on_start : Nil
    start_tick(TICK_INTERVAL) { tick }
  end

  private def tick : Nil
    reload_theme_if_changed
    @flash_frames -= 1 if @flash_frames > 0
    @toast_frames -= 1 if @toast_frames > 0
    rebuild
  end

  def render : Ori::Box
    node = CalendarNode.new(
      year: @year, month: @month, cursor_day: @cursor_day,
      today: @today, monday_first: @monday_first,
      theme: @theme, theme_mtime: @theme_mtime,
      flash_frames: @flash_frames, toast_frames: @toast_frames,
      toast_text: @toast_text,
      style: Ori::S.new(focusable: true, flex: 1),
    )
    Ori::Box.new([node] of Ori::Node, style: Ori::S.new(bg: @theme["background"]? || "#000000", direction: :vertical))
  end

  def handle_key(key : Ori::Key) : Bool
    if key.ctrl
      case
      when key.code.left?  then prev_month; clamp_cursor; return true
      when key.code.right? then next_month; clamp_cursor; return true
      when key.code.up?    then @year -= 1; clamp_cursor; return true
      when key.code.down?  then @year += 1; clamp_cursor; return true
      when key.text == "c" then @running = false; return false
      end
    else
      case
      when key.code.left? || key.text == "h"  then move_left; return true
      when key.code.right? || key.text == "l" then move_right; return true
      when key.code.up? || key.text == "k"    then move_up; return true
      when key.code.down? || key.text == "j"  then move_down; return true
      when key.text == "H"                    then prev_month; clamp_cursor; return true
      when key.text == "L"                    then next_month; clamp_cursor; return true
      when key.text == "K"                    then @year -= 1; clamp_cursor; return true
      when key.text == "J"                    then @year += 1; clamp_cursor; return true
      when key.text == "t"
        @year = @today.year; @month = @today.month; @cursor_day = @today.day
        return true
      when key.text == "m"
        @monday_first = !@monday_first
        clamp_cursor
        save_settings
        return true
      when key.text == "q" then @running = false; return false
      end
    end
    super
  end

  def on_mouse(mouse : Ori::Mouse) : Bool
    case mouse.action
    when Ori::Mouse::Action::Wheel
      if mouse.button.wheel_up?
        move_up
      elsif mouse.button.wheel_down?
        move_down
      end
      true
    else
      false
    end
  end

  private def move_left : Nil
    @cursor_day -= 1
    if @cursor_day < 1
      prev_month
      @cursor_day = days_in_current_month
    end
  end

  private def move_right : Nil
    @cursor_day += 1
    if @cursor_day > days_in_current_month
      next_month
      @cursor_day = 1
    end
  end

  private def move_up : Nil
    col = day_column(@cursor_day)
    @cursor_day -= 7
    if @cursor_day < 1
      prev_month
      @cursor_day = last_day_in_col(col)
    end
  end

  private def move_down : Nil
    col = day_column(@cursor_day)
    @cursor_day += 7
    if @cursor_day > days_in_current_month
      next_month
      @cursor_day = first_day_in_col(col)
    end
  end

  private def prev_month : Nil
    @month -= 1
    if @month < 1
      @month = 12
      @year -= 1
    end
  end

  private def next_month : Nil
    @month += 1
    if @month > 12
      @month = 1
      @year += 1
    end
  end

  private def grid_wday(day_of_week_value : Int32) : Int32
    wday = day_of_week_value % 7
    @monday_first ? (wday + 6) % 7 : wday
  end

  private def start_wday : Int32
    grid_wday(Time.utc(@year, @month, 1).day_of_week.value)
  end

  private def day_column(day : Int32) : Int32
    (start_wday + day - 1) % 7
  end

  private def clamp_cursor : Nil
    max = days_in_current_month
    @cursor_day = max if @cursor_day > max
    @cursor_day = 1 if @cursor_day < 1
  end

  private def days_in_current_month : Int32
    ny = @month == 12 ? @year + 1 : @year
    nm = @month == 12 ? 1 : @month + 1
    (Time.utc(ny, nm, 1) - Time.utc(@year, @month, 1)).days.to_i
  end

  private def last_day_in_col(col : Int32) : Int32
    sw = start_wday
    dim = days_in_current_month
    d = col - sw + 1
    while d < 1
      d += 7
    end
    while d + 7 <= dim
      d += 7
    end
    d
  end

  private def first_day_in_col(col : Int32) : Int32
    d = col - start_wday + 1
    while d < 1
      d += 7
    end
    d
  end

  private def reload_theme_if_changed : Nil
    return unless File.exists?(THEME_PATH)
    mtime = File.info(THEME_PATH).modification_time
    return if mtime == @theme_mtime
    first_load = @theme_mtime.nil?
    @theme_mtime = mtime
    @theme = load_theme
    unless first_load
      @flash_frames = FLASH_DURATION
      @toast_frames = TOAST_DURATION
      name_path = Path.home / ".config/omarchy/current/theme.name"
      name = File.exists?(name_path) ? File.read(name_path).strip : ""
      @toast_text = name.empty? ? "Theme updated" : "Theme: #{name}"
    end
  rescue IO::Error
    @theme = {} of String => String
  end

  private def load_theme : Hash(String, String)
    colors = {} of String => String
    if File.exists?(THEME_PATH)
      File.each_line(THEME_PATH) do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')
        if m = stripped.match(/^(\w+)\s*=\s*"([^"]*)"$/)
          colors[m[1]] = m[2]
        end
      end
    end
    colors
  rescue IO::Error
    {} of String => String
  end

  private def load_settings : Bool
    return false unless File.exists?(SETTINGS_PATH)
    raw = File.read(SETTINGS_PATH)
    json = JSON.parse(raw)
    json["first_day"]?.try(&.as_s) == "monday" || false
  rescue
    false
  end

  private def save_settings : Nil
    Dir.mkdir_p(SETTINGS_DIR) unless Dir.exists?(SETTINGS_DIR)
    File.write(SETTINGS_PATH, JSON.build do |json|
      json.object do
        json.field "first_day", @monday_first ? "monday" : "sunday"
      end
    end)
  end
end

CalendarApp.run
