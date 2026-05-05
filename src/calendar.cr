require "crubbletea"
require "time"
require "json"

struct TickMsg
  include Crubbletea::Msg
end

module Calendar
  VERSION = "0.1.0"

  THEME_PATH = Path.home / ".config/omarchy/current/theme/colors.toml"
  SETTINGS_DIR = Path.home / ".config/calendar"
  SETTINGS_PATH = SETTINGS_DIR / "settings.json"

  DAY_NAMES_SUN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  DAY_NAMES_MON = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

  MONTH_NAMES = {
    1  => "January", 2  => "February", 3  => "March",
    4  => "April",   5  => "May",      6  => "June",
    7  => "July",    8  => "August",    9  => "September",
    10 => "October", 11 => "November", 12 => "December",
  }

  DIGITS = [
    [[1,1,1],[1,0,1],[1,0,1],[1,0,1],[1,1,1]],
    [[0,1,0],[1,1,0],[0,1,0],[0,1,0],[1,1,1]],
    [[1,1,1],[0,0,1],[1,1,1],[1,0,0],[1,1,1]],
    [[1,1,1],[0,0,1],[1,1,1],[0,0,1],[1,1,1]],
    [[1,0,1],[1,0,1],[1,1,1],[0,0,1],[0,0,1]],
    [[1,1,1],[1,0,0],[1,1,1],[0,0,1],[1,1,1]],
    [[1,1,1],[1,0,0],[1,1,1],[1,0,1],[1,1,1]],
    [[1,1,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1]],
    [[1,1,1],[1,0,1],[1,1,1],[1,0,1],[1,1,1]],
    [[1,1,1],[1,0,1],[1,1,1],[0,0,1],[1,1,1]],
  ]

  TICK_INTERVAL = 33.milliseconds

  class App
    include Crubbletea::Model

    @year : Int32
    @month : Int32
    @cursor_day : Int32
    @today : Time
    @width : Int32
    @height : Int32
    @theme : Hash(String, String)
    @theme_mtime : Time?
    FLASH_DURATION = 8
    TOAST_DURATION = 90

    @toast_frames : Int32
    @toast_text : String

    def initialize
      @today = Time.utc
      @year = @today.year
      @month = @today.month
      @cursor_day = @today.day
      @width = 80
      @height = 24
      @theme = {} of String => String
      @theme_mtime = nil
      @flash_frames = 0
      @toast_frames = 0
      @toast_text = ""
      @monday_first = load_settings
      reload_theme_if_changed
    end

    def reload_theme_if_changed
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
    end

    def load_theme : Hash(String, String)
      colors = {} of String => String
      if File.exists?(THEME_PATH)
        File.each_line(THEME_PATH) do |line|
          next if (line = line.strip).empty? || line.starts_with?('#')
          if m = line.match(/^(\w+)\s*=\s*"([^"]*)"$/)
            colors[m[1]] = m[2]
          end
        end
      end
      colors
    end

    def load_settings : Bool
      return false unless File.exists?(SETTINGS_PATH)
      raw = File.read(SETTINGS_PATH)
      json = JSON.parse(raw)
      json["first_day"]?.try(&.as_s) == "monday" || false
    rescue
      false
    end

    def save_settings
      Dir.mkdir_p(SETTINGS_DIR) unless Dir.exists?(SETTINGS_DIR)
      File.write(SETTINGS_PATH, JSON.build do |json|
        json.object do
          json.field "first_day", @monday_first ? "monday" : "sunday"
        end
      end)
    end

    def day_names : Array(String)
      @monday_first ? DAY_NAMES_MON : DAY_NAMES_SUN
    end

    def grid_wday(day_of_week_value : Int32) : Int32
      wday = day_of_week_value % 7
      @monday_first ? (wday + 6) % 7 : wday
    end

    def t(key : String, fallback : String) : String
      @theme[key]? || fallback
    end

    def bg; t("background", "#000000"); end
    def fg; t("foreground", "#ffffff"); end
    def accent; t("accent", "#888888"); end
    def dim; t("color8", "#666666"); end
    def red; t("color1", "#ff0000"); end
    def green; t("color10", "#00ff00"); end
    def yellow; t("color11", "#ffff00"); end
    def cyan; t("color6", "#00ffff"); end
    def pink; t("color5", "#ff00ff"); end
    def cream; t("color7", "#ffffff"); end
    def color0; t("color0", "#333333"); end

    def init : Crubbletea::Cmd?
      schedule_tick
    end

    def schedule_tick : Crubbletea::Cmd?
      Crubbletea.every(TICK_INTERVAL) { TickMsg.new.as(Crubbletea::Msg) }
    end

    def update(msg)
      case msg
      when Crubbletea::KeyPressMsg
        model, cmd = handle_key(msg)
        if cmd
          {model, cmd}
        else
          {model, schedule_tick}
        end
      when Crubbletea::WindowSizeMsg
        @width = msg.width
        @height = msg.height
        {self, schedule_tick}
      when TickMsg
        reload_theme_if_changed
        if @flash_frames > 0
          @flash_frames -= 1
        end
        if @toast_frames > 0
          @toast_frames -= 1
        end
        {self, schedule_tick}
      else
        {self, nil}
      end
    end

    def handle_key(msg : Crubbletea::KeyPressMsg)
      key = msg.key

      if key.ctrl
        if key.code.left?
          prev_month; clamp_cursor; {self, nil}
        elsif key.code.right?
          next_month; clamp_cursor; {self, nil}
        elsif key.code.up?
          @year -= 1; clamp_cursor; {self, nil}
        elsif key.code.down?
          @year += 1; clamp_cursor; {self, nil}
        elsif key.text == "c"
          {self, Crubbletea.quit}
        else
          {self, nil}
        end
      else
        if key.code.left? || (key.code.unknown? && key.text == "h")
          move_left; {self, nil}
        elsif key.code.right? || (key.code.unknown? && key.text == "l")
          move_right; {self, nil}
        elsif key.code.up? || (key.code.unknown? && key.text == "k")
          move_up; {self, nil}
        elsif key.code.down? || (key.code.unknown? && key.text == "j")
          move_down; {self, nil}
        elsif key.code.unknown? && key.text == "H"
          prev_month; clamp_cursor; {self, nil}
        elsif key.code.unknown? && key.text == "L"
          next_month; clamp_cursor; {self, nil}
        elsif key.code.unknown? && key.text == "K"
          @year -= 1; clamp_cursor; {self, nil}
        elsif key.code.unknown? && key.text == "J"
          @year += 1; clamp_cursor; {self, nil}
        elsif key.code.unknown? && key.text == "t"
          @year = @today.year
          @month = @today.month
          @cursor_day = @today.day
          {self, nil}
        elsif key.code.unknown? && key.text == "m"
          @monday_first = !@monday_first
          clamp_cursor
          save_settings
          {self, nil}
        elsif key.code.unknown? && key.text == "q"
          {self, Crubbletea.quit}
        else
          {self, nil}
        end
      end
    end

    def days_in_current_month : Int32
      ny = @month == 12 ? @year + 1 : @year
      nm = @month == 12 ? 1 : @month + 1
      (Time.utc(ny, nm, 1) - Time.utc(@year, @month, 1)).days.to_i
    end

    def month_info : {Int32, Int32}
      first_day = Time.utc(@year, @month, 1)
      start_wday = grid_wday(first_day.day_of_week.value)
      {start_wday, days_in_current_month}
    end

    def start_wday : Int32
      grid_wday(Time.utc(@year, @month, 1).day_of_week.value)
    end

    def day_column(day : Int32) : Int32
      (start_wday + day - 1) % 7
    end

    def clamp_cursor
      max = days_in_current_month
      @cursor_day = max if @cursor_day > max
      @cursor_day = 1 if @cursor_day < 1
    end

    def move_left
      @cursor_day -= 1
      if @cursor_day < 1
        prev_month
        @cursor_day = days_in_current_month
      end
    end

    def move_right
      @cursor_day += 1
      if @cursor_day > days_in_current_month
        next_month
        @cursor_day = 1
      end
    end

    def move_up
      col = day_column(@cursor_day)
      @cursor_day -= 7
      if @cursor_day < 1
        prev_month
        @cursor_day = last_day_in_col(col)
      end
    end

    def move_down
      col = day_column(@cursor_day)
      @cursor_day += 7
      dim = days_in_current_month
      if @cursor_day > dim
        next_month
        @cursor_day = first_day_in_col(col)
      end
    end

    def last_day_in_col(col : Int32) : Int32
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

    def first_day_in_col(col : Int32) : Int32
      sw = start_wday
      d = col - sw + 1
      while d < 1
        d += 7
      end
      d
    end

    def prev_month
      @month -= 1
      if @month < 1
        @month = 12
        @year -= 1
      end
    end

    def next_month
      @month += 1
      if @month > 12
        @month = 1
        @year += 1
      end
    end

    def view : Crubbletea::View
      Crubbletea::View.new(
        content: build_view,
        alt_screen: true,
        background_color: bg,
      )
    end

    def week_count : Int32
      sw, dm = month_info
      (sw + dm + 6) // 7
    end

    def calc_scale(cell_w : Int32, cell_h : Int32) : Int32
      sw = (cell_w - 2) // 7
      sh = (cell_h - 2) // 5
      s = {sw, sh}.min
      s < 1 ? 0 : s
    end

    def render_number(n : Int32, scale : Int32, cell_w : Int32) : Array(String)
      if scale < 1
        return [Crubbletea::Lipgloss::Style.new
          .width(cell_w)
          .align(Crubbletea::Lipgloss::Style::Pos::Center)
          .render(n.to_s)]
      end

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

    def style_day(rendered : Array(String), today : Bool, selected : Bool) : Array(String)
      if today && selected
        sfg = bg
        sbg = yellow
      elsif today
        sfg = bg
        sbg = cyan
      elsif selected
        sfg = cream
        sbg = pink
      else
        return rendered
      end

      rendered.map do |row|
        Crubbletea::Lipgloss::Style.new
          .bold(true)
          .foreground(sfg)
          .background(sbg)
          .render(row)
      end
    end

    def flash_color : String
      return accent if @flash_frames <= 0
      t = @flash_frames.to_f / FLASH_DURATION
      r1, g1, b1 = hex_to_rgb(accent)
      r2, g2, b2 = 255, 255, 255
      r = (r1 + (r2 - r1) * t).to_i.clamp(0, 255)
      g = (g1 + (g2 - g1) * t).to_i.clamp(0, 255)
      b = (b1 + (b2 - b1) * t).to_i.clamp(0, 255)
      "##{r.to_s(16).rjust(2, '0')}#{g.to_s(16).rjust(2, '0')}#{b.to_s(16).rjust(2, '0')}"
    end

    def hex_to_rgb(hex : String) : {Int32, Int32, Int32}
      h = hex.lchop('#')
      return {0, 0, 0} if h.size < 6
      {h[0..1].to_i(16), h[2..3].to_i(16), h[4..5].to_i(16)}
    end

    def pad_line(line : String, width : Int32) : String
      visible = Crubbletea::Lipgloss.width(line)
      return line if visible >= width
      line + " " * (width - visible)
    end

    def build_view : String
      inner_w = @width
      inner_h = @height

      nw = week_count
      fixed = 5
      avail_h = inner_h - fixed
      cell_w = inner_w // 7
      cell_h = avail_h // nw
      scale = calc_scale(cell_w, cell_h)

      lines = [] of String

      lines << pad_line(Crubbletea::Lipgloss::Style.new
        .bold(true)
        .foreground(flash_color)
        .width(inner_w)
        .align(Crubbletea::Lipgloss::Style::Pos::Center)
        .render("#{MONTH_NAMES[@month]} #{@year}"), inner_w)
      lines << " " * inner_w

      dh_style = Crubbletea::Lipgloss::Style.new
        .foreground(yellow)
        .bold(true)
        .width(cell_w)
        .align(Crubbletea::Lipgloss::Style::Pos::Center)
      lines << pad_line(day_names.map { |d| dh_style.render(d) }.join, inner_w)
      lines << " " * inner_w

      sw, days_in_month = month_info
      digit_h = scale < 1 ? 1 : 5 * scale
      pad_top = (cell_h - digit_h) // 2
      pad_bottom = cell_h - digit_h - pad_top

      offset = sw
      week = Array(Tuple(Array(String), Bool, Bool)).new(7) { {[] of String, false, false} }

      (1..days_in_month).each do |day|
        rendered = render_number(day, scale, cell_w)
        today = is_today(day)
        selected = day == @cursor_day
        week[offset] = {style_day(rendered, today, selected), today, selected}
        offset += 1
        if offset > 6
          emit_week(lines, week, digit_h, pad_top, pad_bottom, cell_w, inner_w)
          week = Array(Tuple(Array(String), Bool, Bool)).new(7) { {[] of String, false, false} }
          offset = 0
        end
      end

      if week.any? { |c| c[0].any? }
        emit_week(lines, week, digit_h, pad_top, pad_bottom, cell_w, inner_w)
      end

      while lines.size < inner_h - 2
        lines << " " * inner_w
      end

      if @toast_frames > 0
        alpha = @toast_frames.to_f / TOAST_DURATION
        tr, tg, tb = hex_to_rgb(accent)
        br, bg_i, bb = hex_to_rgb(bg)
        r = (br + (tr - br) * alpha).to_i.clamp(0, 255)
        g = (bg_i + (tg - bg_i) * alpha).to_i.clamp(0, 255)
        b = (bb + (tb - bb) * alpha).to_i.clamp(0, 255)
        toast_fg = "##{r.to_s(16).rjust(2, '0')}#{g.to_s(16).rjust(2, '0')}#{b.to_s(16).rjust(2, '0')}"
        toast_style = Crubbletea::Lipgloss::Style.new
          .foreground(toast_fg)
          .width(inner_w)
          .align(Crubbletea::Lipgloss::Style::Pos::Center)
        lines << pad_line(toast_style.render(" #{@toast_text} "), inner_w)
      else
        lines << " " * inner_w
      end

      lines << pad_line(Crubbletea::Lipgloss::Style.new
        .foreground(dim)
        .width(inner_w)
        .align(Crubbletea::Lipgloss::Style::Pos::Center)
        .render("hjkl: move  H/L: month  J/K: year  m: monday first  t: today  q: quit"), inner_w)

      lines.join("\n")
    end

    def emit_week(
      lines : Array(String),
      week : Array(Tuple(Array(String), Bool, Bool)),
      digit_h : Int32,
      pad_top : Int32,
      pad_bottom : Int32,
      cell_w : Int32,
      inner_w : Int32
    )
      empty_row = " " * inner_w
      pad_top.times { lines << empty_row }
      digit_h.times do |r|
        row = (0...7).map do |col|
          rendered = week[col][0]
          rendered.size > r ? rendered[r] : " " * cell_w
        end.join
        lines << pad_line(row, inner_w)
      end
      pad_bottom.times { lines << empty_row }
    end

    def is_today(day : Int32) : Bool
      @today.year == @year && @today.month == @month && @today.day == day
    end
  end

end

Crubbletea::Program(Calendar::App).new(Calendar::App.new).run
