module CatalogMatch
  # A simple line drawing of a catalog item, generated from its own catalog
  # fields (form, sizes, wall, drilled shank, shot or grit). It is a drawing of
  # the spec, not a product photo, and the page says so.
  #
  # Output is an inline SVG string. Only numbers and escaped labels go into it.
  class Drawing
    WIDTH = 240
    HEIGHT = 160

    def self.svg(item) = new(item).svg

    def initialize(item)
      @item = item
    end

    def svg
      body = case @item["form"]
             when "sheet", "plate" then slab
             when "square tube" then square_tube
             when "angle" then angle
             when "flat bar" then flat_bar
             when "round bar" then round_bar
             when "pipe" then pipe
             when "bolt" then bolt
             when "ingot" then ingot
             when "sow" then sow
             when "abrasive" then abrasive
             else unknown
             end
      %(<svg class="item-drawing" viewBox="0 0 #{WIDTH} #{HEIGHT}" role="img" aria-label="#{h(label)}" xmlns="http://www.w3.org/2000/svg">) +
        %(<title>#{h(label)}</title>#{body}</svg>)
    end

    private

    def label
      "Drawing of #{@item['pn']} from its catalog dimensions: #{@item['description']}"
    end

    # Sheet or plate: an oblique slab, thicker for plate, proportional plan size.
    def slab
      width = @item["width_in"].to_f
      length = @item["length_in"].to_f
      scale = 150 / [ width, length, 1 ].max
      w = (length * scale).clamp(40, 150)
      d = (width * scale * 0.45).clamp(16, 60)
      t = [ (@item["thickness_in"].to_f * 40).clamp(3, 18), 3 ].max
      x = 30
      y = 40
      top = [ [ x, y + d ], [ x + d, y ], [ x + d + w, y ], [ x + w, y + d ] ]
      front = [ [ x, y + d ], [ x + w, y + d ], [ x + w, y + d + t ], [ x, y + d + t ] ]
      side = [ [ x + w, y + d ], [ x + d + w, y ], [ x + d + w, y + t ], [ x + w, y + d + t ] ]
      polygon(top, "item-drawing__face") + polygon(front, "item-drawing__edge") + polygon(side, "item-drawing__edge") +
        text(x + w / 2, y + d + t + 22, "#{fmt(length)} in") +
        text(x + w + d / 2 + 18, y + d / 2 + 4, "#{fmt(width)} in", anchor: "start") +
        text(x, y - 12, thickness_label, anchor: "start")
    end

    def square_tube
      size = @item["size_a_in"].to_f
      wall = @item["wall_in"].to_f
      outer = 90
      inner_gap = [ (wall / [ size, 0.01 ].max * outer), 4 ].max
      x = 35
      y = 25
      rect(x, y, outer, outer, "item-drawing__face") +
        rect(x + inner_gap, y + inner_gap, outer - 2 * inner_gap, outer - 2 * inner_gap, "item-drawing__hole") +
        text(x + outer / 2, y + outer + 22, "#{fmt(size)} x #{fmt(size)} in") +
        text(150, 60, "wall #{wall} in", anchor: "start") +
        text(150, 80, length_label, anchor: "start")
    end

    def angle
      leg = 90
      t = [ (@item["thickness_in"].to_f / [ @item["size_a_in"].to_f, 0.01 ].max * leg), 6 ].max
      x = 35
      y = 25
      polygon([ [ x, y ], [ x + t, y ], [ x + t, y + leg - t ], [ x + leg, y + leg - t ], [ x + leg, y + leg ], [ x, y + leg ] ], "item-drawing__face") +
        text(x + leg / 2, y + leg + 22, "#{fmt(@item['size_a_in'])} x #{fmt(@item['size_b_in'])} x #{fmt(@item['thickness_in'])} in") +
        text(150, 60, length_label, anchor: "start")
    end

    def flat_bar
      w = 150
      t = [ (@item["thickness_in"].to_f / [ @item["width_in"].to_f, 0.01 ].max * 40), 4 ].max
      rect(45, 60, w, t, "item-drawing__face") + rect(45, 60 + t, w, 4, "item-drawing__edge") +
        text(120, 60 + t + 30, "#{fmt(@item['width_in'])} in wide x #{fmt(@item['thickness_in'])} in") +
        text(120, 45, length_label)
    end

    def round_bar
      r = 32
      circle(60, 75, r, "item-drawing__face") +
        rect(60, 75 - r, 130, 2 * r, "item-drawing__edge") + circle(190, 75, r, "item-drawing__face") +
        text(60, 135, "#{fmt(@item['diameter_in'])} in dia") + text(150, 30, length_label)
    end

    def pipe
      circle(70, 75, 42, "item-drawing__face") + circle(70, 75, 32, "item-drawing__hole") +
        text(70, 140, "#{fmt(@item['nps'])} in NPS, sch #{@item['schedule']}") +
        text(130, 60, @item["process"].to_s, anchor: "start") + text(130, 80, length_label, anchor: "start")
    end

    def bolt
      diameter = @item["diameter_in"].to_f
      length = @item["nominal_length_in"].to_f
      grip = @item["grip_length_in"].to_f
      shank_h = (diameter * 90).clamp(10, 40)
      shank_w = (length * 70).clamp(60, 160)
      grip_w = length.positive? ? shank_w * (grip / length) : shank_w * 0.7
      x = 50
      y = 75 - shank_h / 2
      head = polygon([ [ x - 24, y - 8 ], [ x, y - 8 ], [ x, y + shank_h + 8 ], [ x - 24, y + shank_h + 8 ] ], "item-drawing__face")
      threads = ((x + grip_w).to_i..(x + shank_w - 4).to_i).step(6).map do |thread_x|
        %(<line class="item-drawing__line" x1="#{thread_x}" y1="#{fmt(y)}" x2="#{thread_x + 4}" y2="#{fmt(y + shank_h)}"/>)
      end.join
      hole = @item["shank_drilled"] ? circle(x + shank_w - 8, 75, 3, "item-drawing__hole") : ""
      head + rect(x, y, shank_w, shank_h, "item-drawing__edge") + threads + hole +
        text(x + grip_w / 2, y + shank_h + 26, "grip #{@item['grip_length_display'] || fmt(grip)} in") +
        text(x + shank_w / 2, y - 14, "#{@item['thread']} x #{@item['nominal_length_display'] || fmt(length)} in") +
        text(x + shank_w / 2, 150, @item["shank_drilled"] ? "drilled shank" : "undrilled shank")
    end

    def ingot
      polygon([ [ 40, 95 ], [ 60, 60 ], [ 180, 60 ], [ 200, 95 ] ], "item-drawing__face") +
        polygon([ [ 40, 95 ], [ 200, 95 ], [ 200, 110 ], [ 40, 110 ] ], "item-drawing__edge") +
        (1..4).map { |i| %(<line class="item-drawing__line" x1="#{40 + i * 32}" y1="62" x2="#{40 + i * 32}" y2="108"/>) }.join +
        text(120, 135, "#{@item['grade']} #{@item['form_detail']}")
    end

    def sow
      polygon([ [ 50, 100 ], [ 75, 50 ], [ 165, 50 ], [ 190, 100 ] ], "item-drawing__face") +
        polygon([ [ 50, 100 ], [ 190, 100 ], [ 190, 120 ], [ 50, 120 ] ], "item-drawing__edge") +
        text(120, 145, "#{@item['grade']} #{@item['form_detail']}")
    end

    # Shot is round; grit and mineral media are angular. Particle size is
    # drawn relative to the size number so S-780 looks larger than S-170.
    def abrasive
      grade = @item["grade"].to_s
      size_number = grade[/\d+/].to_i
      spherical = grade.start_with?("S-") || @item["material"].to_s.include?("bead")
      radius = spherical ? (3 + size_number / 90.0).clamp(3, 12) : 6
      random = Random.new(@item["pn"].sum)
      particles = 26.times.map do
        cx = random.rand(30..210)
        cy = random.rand(20..115)
        if spherical
          circle(cx, cy, radius, "item-drawing__face")
        else
          points = 5.times.map { |i| angle = i * 1.256 + random.rand * 0.6; [ cx + Math.cos(angle) * radius * (0.6 + random.rand), cy + Math.sin(angle) * radius * (0.6 + random.rand) ] }
          polygon(points, "item-drawing__face")
        end
      end.join
      particles + text(120, 145, [ grade, @item["size"] ].compact.join("  ·  "))
    end

    def unknown
      text(120, 80, "No drawing for this form")
    end

    def thickness_label
      @item["gauge"] ? "#{@item['gauge']} ga (#{@item['thickness_in']} in)" : "#{fmt(@item['thickness_in'])} in thick"
    end

    def length_label
      @item["length_in"] ? "#{fmt(@item['length_in'].to_f / 12)} ft length" : ""
    end

    def polygon(points, css_class)
      %(<polygon class="#{css_class}" points="#{points.map { |px, py| "#{fmt(px)},#{fmt(py)}" }.join(' ')}"/>)
    end

    def rect(x, y, w, hgt, css_class)
      %(<rect class="#{css_class}" x="#{fmt(x)}" y="#{fmt(y)}" width="#{fmt(w)}" height="#{fmt(hgt)}"/>)
    end

    def circle(cx, cy, r, css_class)
      %(<circle class="#{css_class}" cx="#{fmt(cx)}" cy="#{fmt(cy)}" r="#{fmt(r)}"/>)
    end

    def text(x, y, content, anchor: "middle")
      %(<text class="item-drawing__label" x="#{fmt(x)}" y="#{fmt(y)}" text-anchor="#{anchor}">#{h(content)}</text>)
    end

    def fmt(value)
      number = value.to_f
      number == number.round ? number.round.to_s : number.round(3).to_s
    end

    def h(value) = ERB::Util.html_escape(value.to_s)
  end
end
