class CanvizTokenizer
  constructor: (@str) ->

  takeChars: (num) ->
    num = 1 if !num
    tokens = []
    while (num--)
      matches = @str.match(/^(\S+)\s*/)
      if matches
        @str = @str.substr(matches[0].length)
        tokens.push(matches[1])
      else
        tokens.push(false)

    if 1 == tokens.length
      return tokens[0]
    else
      return tokens

  takeNumber: (num) ->
    num = 1 if !num
    if 1 == num
      return Number(@takeChars())
    else
      tokens = @takeChars(num)
      while num--
        tokens[num] = Number(tokens[num])
      return tokens

  takeString: () ->
    byteCount = Number(@takeChars())
    charCount = 0
    return false if '-' != @str.charAt(0)

    while 0 < byteCount
      ++charCount
      charCode = @str.charCodeAt(charCount)
      if 0x80 > charCode
        --byteCount
      else if 0x800 > charCode
        byteCount -= 2
      else
        byteCount -= 3

    str = @str.substr(1, charCount)
    @str = @str.substr(1 + charCount).replace(/^\s+/, '')
    return str

class CanvizEntity
  constructor: (@defaultAttrHashName, @name, @canviz, @rootGraph, @parentGraph, @immediateGraph) ->
    @attrs = {}
    @drawAttrs = {}

  initBB: () ->
    matches = @getAttr('pos').match(/([0-9.]+),([0-9.]+)/)
    x = Math.round(matches[1])
    y = Math.round(@canviz.height - matches[2])
    @bbRect = new Rect(x, y, x, y)

  getAttr: (attrName, escString=false) ->
    attrValue = @attrs[attrName]
    if not attrValue?
      graph = @parentGraph
      while graph?
        attrValue = graph[@defaultAttrHashName][attrName]
        if not attrValue?
          graph = graph.parentGraph
        else
          break

    if attrValue and escString
      attrValue = attrValue.replace @escStringMatchRe, (match, p1) =>
        switch p1
          when 'N', 'E' then return @name
          when 'T' then return @tailNode
          when 'H' then return @headNode
          when 'G' then return @immediateGraph.name
          when 'L' then return @getAttr('label', true)
        return match
    return attrValue

  draw: (ctx, ctxScale, redrawCanvasOnly) ->
    if !redrawCanvasOnly
      @initBB()
      bbDiv = document.createElement('div')
      @canviz.elements.appendChild(bbDiv)

    for _, command of @drawAttrs
      # command = drawAttr.value

      tokenizer = new CanvizTokenizer(command)
      token = tokenizer.takeChars()
      if token
        dashStyle = 'solid'
        ctx.save()
        while token
          switch token
            when 'E', 'e' # unfilled ellipse
              filled = ('E' == token)
              cx = tokenizer.takeNumber()
              cy = @canviz.height - tokenizer.takeNumber()
              rx = tokenizer.takeNumber()
              ry = tokenizer.takeNumber()
              path = new Ellipse(cx, cy, rx, ry)
            when 'P', 'p', 'L'
              filled = ('P' == token)
              closed = ('L' != token);
              numPoints = tokenizer.takeNumber()
              tokens = tokenizer.takeNumber(2 * numPoints)
              path = new Path()
              #for (i = 2; i < 2 * numPoints; i += 2)
              for i in [2...(2*numPoints)] by 2
                path.addBezier([
                  new Point(tokens[i - 2], @canviz.height - tokens[i - 1])
                  new Point(tokens[i],     @canviz.height - tokens[i + 1])
                ])

              if closed
                path.addBezier([
                  new Point(tokens[2 * numPoints - 2], @canviz.height - tokens[2 * numPoints - 1])
                  new Point(tokens[0],                 @canviz.height - tokens[1])
                ])

            when 'B', 'b' # unfilled b-spline
              filled = ('b' == token)
              numPoints = tokenizer.takeNumber()
              tokens = tokenizer.takeNumber(2 * numPoints); # points
              path = new Path()
              for i in [2...(2*numPoints)] by 6
                path.addBezier([
                  new Point(tokens[i - 2], @canviz.height - tokens[i - 1])
                  new Point(tokens[i],     @canviz.height - tokens[i + 1])
                  new Point(tokens[i + 2], @canviz.height - tokens[i + 3])
                  new Point(tokens[i + 4], @canviz.height - tokens[i + 5])
                ])

            when 'I' # image
              l = tokenizer.takeNumber()
              b = @canviz.height - tokenizer.takeNumber()
              w = tokenizer.takeNumber()
              h = tokenizer.takeNumber()
              src = tokenizer.takeString()
              if !@canviz.images[src]
                @canviz.images[src] = new CanvizImage(@canviz, src)
              @canviz.images[src].draw(ctx, l, b - h, w, h)

            when 'T' # text
              l = Math.round(ctxScale * tokenizer.takeNumber() + @canviz.padding)
              t = Math.round(ctxScale * @canviz.height + 2 * @canviz.padding - (ctxScale * (tokenizer.takeNumber() + @canviz.bbScale * fontSize) + @canviz.padding))
              textAlign = tokenizer.takeNumber()
              textWidth = Math.round(ctxScale * tokenizer.takeNumber())
              str = tokenizer.takeString()
              if !redrawCanvasOnly and !/^\s*$/.test(str)
                #str = escapeHTML(str)
                loop
                  matches = str.match(/[ ]([ ]+)/)
                  if matches
                    spaces = ' '
                    spaces += '&nbsp;' for _ in [0..matches[1].length.times]
                    str = str.replace(/[ ] +/, spaces)
                  break unless matches

                href = @getAttr('URL', true) || @getAttr('href', true)
                if href
                  target = @getAttr('target', true) || '_self'
                  tooltip = @getAttr('tooltip', true) || @getAttr('label', true)
                  text = document.createElement("a")
                  text.href = href
                  text.target = target
                  text.title = tooltip

                  for attrName in ['onclick', 'onmousedown', 'onmouseup', 'onmouseover', 'onmousemove', 'onmouseout']
                    attrValue = @getAttr(attrName, true)
                    if attrValue
                      text.writeAttribute(attrName, attrValue)
                  text.textDecoration = 'none'
                else
                  text = document.createElement("span") # new Element('span')

                text.innerText = str
                ts = text.style

                ts.fontSize = Math.round(fontSize * ctxScale * @canviz.bbScale) + 'px'
                ts.fontFamily = fontFamily
                ts.color = strokeColor.textColor
                ts.position = 'absolute'
                ts.textAlign = if (-1 == textAlign) then 'left' else if (1 == textAlign) then 'right' else 'center'
                ts.left = (l - (1 + textAlign) * textWidth) + 'px'
                ts.top = t + 'px'
                ts.width = (2 * textWidth) + 'px'

                ts.opacity = strokeColor.opacity if 1 != strokeColor.opacity
                @canviz.elements.appendChild(text)

            when 'C', 'c'
              fill = ('C' == token)
              color = @parseColor(tokenizer.takeString())
              if fill
                fillColor = color
                ctx.fillStyle = color.canvasColor
              else
                strokeColor = color
                ctx.strokeStyle = color.canvasColor

            when 'F' # // set font
              fontSize = tokenizer.takeNumber()
              fontFamily = tokenizer.takeString()
              switch fontFamily
                when 'Times-Roman' then fontFamily = 'Times New Roman'
                when 'Courier' then fontFamily = 'Courier New'
                when 'Helvetica' then fontFamily = 'Arial'

            when 'S'  # // set style
              style = tokenizer.takeString()
              switch style
                when 'solid', 'filled' then  1 # nothing
                when 'dashed', 'dotted' then dashStyle = style
                when 'bold' then ctx.lineWidth = 2
                else
                  matches = style.match(/^setlinewidth\((.*)\)$/)
                  if matches
                    ctx.lineWidth = Number(matches[1])
                  else
                    debug('unknown style ' + style)

            else
              debug('unknown token ' + token)
              return

          if path
            @canviz.drawPath(ctx, path, filled, dashStyle)
            @bbRect.expandToInclude(path.getBB()) if !redrawCanvasOnly
            path = undefined
          token = tokenizer.takeChars()

        if !redrawCanvasOnly
          bbDiv.position = 'absolute'
          bbDiv.left     = Math.round(ctxScale * @bbRect.l + @canviz.padding) + 'px'
          bbDiv.top      = Math.round(ctxScale * @bbRect.t + @canviz.padding) + 'px'
          bbDiv.width    = Math.round(ctxScale * @bbRect.getWidth()) + 'px'
          bbDiv.height   = Math.round(ctxScale * @bbRect.getHeight()) + 'px'
        ctx.restore()

  parseColor: (color) ->
    parsedColor = {opacity: 1}
    # // rgb/rgba
    if /^#(?:[0-9a-f]{2}\s*){3,4}$/i.test(color)
      return @canviz.parseHexColor(color)

    # // hsv
    matches = color.match(/^(\d+(?:\.\d+)?)[\s,]+(\d+(?:\.\d+)?)[\s,]+(\d+(?:\.\d+)?)$/)
    if matches
      parsedColor.canvasColor = parsedColor.textColor = @canviz.hsvToRgbColor(matches[1], matches[2], matches[3])
      return parsedColor
    # // named color
    colorScheme = @getAttr('colorscheme') || 'X11'
    colorName = color
    matches = color.match(/^\/(.*)\/(.*)$/)
    if matches
      if matches[1]
        colorScheme = matches[1]
      colorName = matches[2]
    else
      matches = color.match(/^\/(.*)$/)
      if matches
        colorScheme = 'X11'
        colorName = matches[1]

    colorName = colorName.toLowerCase()
    colorSchemeName = colorScheme.toLowerCase()
    colorSchemeData = Canviz.colors[colorSchemeName]
    if colorSchemeData
      colorData = colorSchemeData[colorName]
      if colorData
        return @canviz.parseHexColor('#' + colorData)
    colorData = Canviz.colors['fallback'][colorName]
    if colorData
      return @canviz.parseHexColor('#' + colorData)

    if !colorSchemeData
      debug('unknown color scheme ' + colorScheme)

    # // unknown
    debug('unknown color ' + color + '; color scheme is ' + colorScheme)
    parsedColor.canvasColor = parsedColor.textColor = '#000000'
    return parsedColor

class CanvizNode extends CanvizEntity
  constructor: (name, canviz, rootGraph, parentGraph) ->
    super('nodeAttrs', name, canviz, rootGraph, parentGraph, parentGraph)
  escStringMatchRe: /\\([NGL])/g

#
class CanvizEdge extends CanvizEntity
  constructor: (name, canviz, rootGraph, parentGraph, @tailNode, @headNode) ->
    super('edgeAttrs', name, canviz, rootGraph, parentGraph, parentGraph)
  escStringMatchRe: /\\([EGTHL])/g

class CanvizGraph extends CanvizEntity
  constructor: (name, canviz, rootGraph, parentGraph) ->
    super('attrs', name, canviz, rootGraph, parentGraph, this)
    @nodeAttrs = {}
    @edgeAttrs = {}
    @nodes = []
    @edges = []
    @subgraphs = []

  initBB: () ->
    coords = @getAttr('bb').split(',')
    @bbRect = new Rect(coords[0], @canviz.height - coords[1], coords[2], @canviz.height - coords[3])

  draw: (ctx, ctxScale, redrawCanvasOnly) ->
    super(ctx, ctxScale, redrawCanvasOnly)
    for type in [@subgraphs, @nodes, @edges]
      for entity in type
        entity.draw(ctx, ctxScale, redrawCanvasOnly)
  escStringMatchRe: /\\([GL])/g


class Canviz
  @maxXdotVersion: "1.2"
  @colors:
    fallback:
      black:'000000'
      lightgrey:'d3d3d3'
      white:'ffffff'

  constructor: (container, url, urlParams) ->
    @canvas = document.createElement('canvas')
    @canvas.style.position = "absolute"
    Canviz.canvasCounter ?= 0
    @canvas.id = 'canviz_canvas_' + (++Canviz.canvasCounter)
    @elements = document.createElement('div')
    @elements.style.position = "absolute"
    @container = document.getElementById(container)
    @container.style.position = "relative"
    @container.appendChild(@canvas)
    @container.appendChild(@elements)
    @ctx = @canvas.getContext('2d')
    @scale = 1
    @padding = 8
    @dashLength = 6
    @dotSpacing = 4
    @graphs = []
    @images = {}
    @numImages = 0
    @numImagesFinished = 0
    @imagePath = ""

    @idMatch = '([a-zA-Z\u0080-\uFFFF_][0-9a-zA-Z\u0080-\uFFFF_]*|-?(?:\\.\\d+|\\d+(?:\\.\\d*)?)|"(?:\\\\"|[^"])*"|<(?:<[^>]*>|[^<>]+?)+>)'
    @nodeIdMatch = @idMatch + '(?::' + @idMatch + ')?(?::' + @idMatch + ')?'

    @graphMatchRe = new RegExp('^(strict\\s+)?(graph|digraph)(?:\\s+' + @idMatch + ')?\\s*{$', 'i')
    @subgraphMatchRe = new RegExp('^(?:subgraph\\s+)?' + @idMatch + '?\\s*{$', 'i')
    @nodeMatchRe = new RegExp('^(' + @nodeIdMatch + ')\\s+\\[(.+)\\];$')
    @edgeMatchRe = new RegExp('^(' + @nodeIdMatch + '\\s*-[->]\\s*' + @nodeIdMatch + ')\\s+\\[(.+)\\];$')
    @attrMatchRe = new RegExp('^' + @idMatch + '=' + @idMatch + '(?:[,\\s]+|$)')


  setScale: (@scale) ->
  setImagePath: (@imagePath) ->

  parse: (xdot) ->
    @graphs = []
    @width = 0
    @height = 0
    @maxWidth = false
    @maxHeight = false
    @bbEnlarge = false
    @bbScale = 1
    @dpi = 96
    @bgcolor = opacity: 1
    @bgcolor.canvasColor = @bgcolor.textColor = '#ffffff'
    lines = xdot.split(/\r?\n/)
    i = 0
    containers = []

    while i < lines.length
      line = lines[i++].replace(/^\s+/, '')
      if '' != line and '#' != line.substr(0, 1)
        while i < lines.length and ';' != (lastChar = line.substr(line.length - 1, line.length)) and '{' != lastChar and '}' != lastChar
          if '\\' == lastChar
            line = line.substr(0, line.length - 1)
          line += lines[i++]

        if containers.length == 0
          matches = line.match(@graphMatchRe)
          if matches
            rootGraph = new CanvizGraph(matches[3], this)
            containers.unshift(rootGraph)
            containers[0].strict = not (not matches[1])
            containers[0].type = if 'graph' == matches[2] then 'undirected' else 'directed'
            containers[0].attrs.xdotversion = '1.0'
            containers[0].attrs.bb ?= '0,0,500,500'
            @graphs.push(containers[0])
        else
          matches = line.match(@subgraphMatchRe)
          if matches
            containers.unshift(new CanvizGraph(matches[1], this, rootGraph, containers[0]))
            containers[1].subgraphs.push containers[0]

        if matches
        else if "}" == line
          containers.shift()
          break if 0 == containers.length
        else
          matches = line.match(@nodeMatchRe)
          if matches
            entityName = matches[2]
            attrs = matches[5]
            drawAttrHash = containers[0].drawAttrs
            isGraph = false
            switch entityName
              when 'graph'
                attrHash = containers[0].attrs
                isGraph = true
              when 'node' then attrHash = containers[0].nodeAttrs
              when 'edge' then attrHash = containers[0].edgeAttrs
              else
                entity = new CanvizNode(entityName, this, rootGraph, containers[0])
                attrHash = entity.attrs
                drawAttrHash = entity.drawAttrs
                containers[0].nodes.push(entity)
          else
            matches = line.match(@edgeMatchRe)
            if matches
              entityName = matches[1]
              attrs = matches[8]
              entity = new CanvizEdge(entityName, this, rootGraph, containers[0], matches[2], matches[5])
              attrHash = entity.attrs
              drawAttrHash = entity.drawAttrs
              containers[0].edges.push(entity)

          while matches
            break if 0 == attrs.length

            matches = attrs.match(@attrMatchRe)
            if matches
              attrs = attrs.substr(matches[0].length)
              attrName = matches[1]
              attrValue = @unescape(matches[2])
              if /^_.*draw_$/.test(attrName)
                drawAttrHash[attrName] = attrValue
              else
                attrHash[attrName] = attrValue

              if isGraph and 1 == containers.length
                switch attrName
                  when 'bb'
                    bb = attrValue.split(/,/)
                    @width  = Number(bb[2])
                    @height = Number(bb[3])
                  when 'bgcolor' then @bgcolor = rootGraph.parseColor(attrValue)
                  when 'dpi' then @dpi = attrValue
                  when 'size'
                    size = attrValue.match(/^(\d+|\d*(?:\.\d+)),\s*(\d+|\d*(?:\.\d+))(!?)$/)
                    if size
                      @maxWidth  = 72 * Number(size[1])
                      @maxHeight = 72 * Number(size[2])
                      @bbEnlarge = '!' == size[3]
                  when 'xdotversion'
                    if 0 > @versionCompare(Canviz.maxXdotVersion, attrHash['xdotversion'])
                      1
    @draw()

  draw: (redrawCanvasOnly) ->
    redrawCanvasOnly ?= false
    ctxScale = @scale * @dpi / 72
    width  = Math.round(ctxScale * @width  + 2 * @padding)
    height = Math.round(ctxScale * @height + 2 * @padding)
    if !redrawCanvasOnly
      @canvas.width  = width
      @canvas.height = height
      @canvas.style.width = "#{width}px"
      @canvas.style.height = "#{height}px"
      @container.style.width = "#{width}px"

      while (@elements.firstChild)
        @elements.removeChild(@elements.firstChild)

    @ctx.save()
    @ctx.lineCap = 'round'
    @ctx.fillStyle = @bgcolor.canvasColor
    @ctx.fillRect(0, 0, width, height)
    @ctx.translate(@padding, @padding)
    @ctx.scale(ctxScale, ctxScale)
    @graphs[0].draw(@ctx, ctxScale, redrawCanvasOnly)
    @ctx.restore()

  drawPath: (ctx, path, filled, dashStyle) ->
    if (filled)
      ctx.beginPath()
      path.makePath(ctx)
      ctx.fill()

    if ctx.fillStyle != ctx.strokeStyle or not filled
      switch dashStyle
        when 'dashed'
          ctx.beginPath()
          path.makeDashedPath(ctx, @dashLength)
        when 'dotted'
          oldLineWidth = ctx.lineWidth
          ctx.lineWidth *= 2
          ctx.beginPath()
          path.makeDottedPath(ctx, @dotSpacing)
        else
          if not filled
            ctx.beginPath()
            path.makePath(ctx)
      ctx.stroke()
      ctx.lineWidth = oldLineWidth if oldLineWidth

  unescape: (str) ->
    matches = str.match(/^"(.*)"$/)
    if (matches)
      return matches[1].replace(/\\"/g, '"')
    else
      return str

  parseHexColor: (color) ->
    matches = color.match(/^#([0-9a-f]{2})\s*([0-9a-f]{2})\s*([0-9a-f]{2})\s*([0-9a-f]{2})?$/i)
    if matches
      canvasColor; textColor = '#' + matches[1] + matches[2] + matches[3]; opacity = 1
      if (matches[4])  # rgba
        opacity = parseInt(matches[4], 16) / 255
        canvasColor = 'rgba(' + parseInt(matches[1], 16) + ',' + parseInt(matches[2], 16) + ',' + parseInt(matches[3], 16) + ',' + opacity + ')'
      else # rgb
        canvasColor = textColor
    return {canvasColor: canvasColor, textColor: textColor, opacity: opacity}

  hsvToRgbColor: (h, s, v) ->
    h *= 360
    i = Math.floor(h / 60) % 6
    f = h / 60 - i
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    switch (i)
      when 0 then r = v; g = t; b = p
      when 1 then r = q; g = v; b = p
      when 2 then r = p; g = v; b = t
      when 3 then r = p; g = q; b = v
      when 4 then r = t; g = p; b = v
      when 5 then r = v; g = p; b = q
    return 'rgb(' + Math.round(255 * r) + ',' + Math.round(255 * g) + ',' + Math.round(255 * b) + ')'

  versionCompare: (a, b) ->
    a = a.split('.')
    b = b.split('.')
    while (a.length or b.length)
      a1 = if a.length then a.shift() else 0
      b1 = if b.length then b.shift() else 0
      return -1 if (a1 < b1)
      return 1 if (a1 > b1)
    return 0

class CanvizImage
  constructor: (@canviz, src) ->
    ++@canviz.numImages
    @finished = @loaded = false
    @img = new Image()
    @img.onload = @onLoad.bind(this)
    @img.onerror = @onFinish.bind(this)
    @img.onabort = @onFinish.bind(this)
    @img.src = @canviz.imagePath + src

  onLoad: ->
    @loaded = true
    @onFinish()

  onFinish: ->
    @finished = true
    ++@canviz.numImagesFinished
    if @canviz.numImages == @canviz.numImagesFinished
      @canviz.draw(true)

  draw: (ctx, l, t, w, h) ->
    if @finished
      if @loaded
        ctx.drawImage(@img, l, t, w, h)
      else
        debug("can't load image " + @img.src)
        @drawBrokenImage(ctx, l, t, w, h)

  drawBrokenImage: (ctx, l, t, w, h) ->
    ctx.save()
    ctx.beginPath()
    new Rect(l, t, l + w, t + w).draw(ctx)
    ctx.moveTo(l, t)
    ctx.lineTo(l + w, t + w)
    ctx.moveTo(l + w, t)
    ctx.lineTo(l, t + h)
    ctx.strokeStyle = '#f00'
    ctx.lineWidth = 1
    ctx.stroke()
    ctx.restore()

##########################################################
# $Id: path.js 262 2009-05-19 11:55:24Z ryandesign.com $
##########################################################

class Point
  constructor: (@x, @y) ->
  offset: (dx, dy) ->
    @x += dx
    @y += dy

  distanceFrom: (point) ->
    dx = @x - point.x
    dy = @y - point.y
    Math.sqrt(dx * dx + dy * dy)

  makePath: (ctx) ->
    ctx.moveTo(@x, @y)
    ctx.lineTo(@x + 0.001, @y)


############### Path.js

class Bezier
  constructor: (@points) ->
    @order = points.length

  reset: () ->
    p = Bezier.prototype
    @controlPolygonLength = p.controlPolygonLength
    @chordLength = p.chordLength
    @triangle = p.triangle
    @chordPoints = p.chordPoints
    @coefficients = p.coefficients

  offset: (dx, dy) ->
    for point in @points
      point.offset(dx, dy)
    @reset()

  getBB: ->
    return undefined if !@order
    p = @points[0]
    l = r = p.x
    t = b = p.y
    for point in @points
      l = Math.min(l, point.x)
      t = Math.min(t, point.y)
      r = Math.max(r, point.x)
      b = Math.max(b, point.y)
    rect = new Rect(l, t, r, b)
    return (@getBB = -> rect)()

  isPointInBB: (x, y, tolerance) ->
    tolerance ?= 0
    bb = @getBB()
    if (0 < tolerance)
      bb = clone(bb)
      bb.inset(-tolerance, -tolerance)
    !(x < bb.l || x > bb.r || y < bb.t || y > bb.b)

  isPointOnBezier: (x, y, tolerance=0) ->
    return false if !@isPointInBB(x, y, tolerance)
    segments = @chordPoints()
    p1 = segments[0].p
    for i in [1...segments.length]
      p2 = segments[i].p
      x1 = p1.x
      y1 = p1.y
      x2 = p2.x
      y2 = p2.y
      bb = new Rect(x1, y1, x2, y2)
      if bb.isPointInBB(x, y, tolerance)
        twice_area = Math.abs(x1 * y2 + x2 * y + x * y1 - x2 * y1 - x * y2 - x1 * y)
        base = p1.distanceFrom(p2)
        height = twice_area / base
        return true if height <= tolerance
      p1 = p2
    return false

  # # Based on Oliver Steele's bezier.js library.
  controlPolygonLength: ->
    len = 0
    for i in [1...@order]
      len += @points[i - 1].distanceFrom(@points[i])
    (@controlPolygonLength = -> len)()

  # # Based on Oliver Steele's bezier.js library.
  chordLength: ->
    len = @points[0].distanceFrom(@points[@order - 1])
    (@chordLength = -> len)()

  # # From Oliver Steele's bezier.js library.
  triangle: ->
    upper = @points
    m = [upper]
    for i in [1...@order]
      lower = []
      for j in [0...(@order-i)]
        c0 = upper[j]
        c1 = upper[j + 1]
        lower[j] = new Point((c0.x + c1.x) / 2, (c0.y + c1.y) / 2)
      m.push(lower)
      upper = lower
    (@triangle = -> m)()

  # # Based on Oliver Steele's bezier.js library.
  triangleAtT: (t) ->
    s = 1 - t
    upper = @points
    m = [upper]
    for i in [1...@order]
      lower = []
      for j in [0...(@order-i)]
        c0 = upper[j]
        c1 = upper[j + 1]
        lower[j] = new Point(c0.x * s + c1.x * t, c0.y * s + c1.y * t)
      m.push(lower)
      upper = lower
    return m

  # Returns two beziers resulting from splitting @bezier at t=0.5.
  # Based on Oliver Steele's bezier.js library.
  split: (t=0.5) ->
    m = if (0.5 == t) then @triangle() else @triangleAtT(t)
    leftPoints  = new Array(@order)
    rightPoints = new Array(@order)
    for i in [1...@order]
      leftPoints[i]  = m[i][0]
      rightPoints[i] = m[@order - 1 - i][i]
    return {left: new Bezier(leftPoints), right: new Bezier(rightPoints)}

  # Returns a bezier which is the portion of @bezier from t1 to t2.
  # Thanks to Peter Zin on comp.graphics.algorithms.
  mid: (t1, t2) ->
    @split(t2).left.split(t1 / t2).right

  # Returns points (and their corresponding times in the bezier) that form
  # an approximate polygonal representation of the bezier.
  # Based on the algorithm described in Jeremy Gibbons' dashed.ps.gz
  chordPoints: ->
    p = [{tStart: 0, tEnd: 0, dt: 0, p: @points[0]}].concat(@_chordPoints(0, 1))
    (@chordPoints = -> p)()

  _chordPoints: (tStart, tEnd) ->
    tolerance = 0.001
    dt = tEnd - tStart
    if @controlPolygonLength() <= (1 + tolerance) * @chordLength()
      return [{tStart: tStart, tEnd: tEnd, dt: dt, p: @points[@order - 1]}]
    else
      tMid = tStart + dt / 2
      halves = @split()
      return halves.left._chordPoints(tStart, tMid).concat(halves.right._chordPoints(tMid, tEnd))

  # Returns an array of times between 0 and 1 that mark the bezier evenly
  # in space.
  # Based in part on the algorithm described in Jeremy Gibbons' dashed.ps.gz
  markedEvery: (distance, firstDistance) ->
    nextDistance = firstDistance || distance
    segments = @chordPoints()
    times = []
    t = 0; # time
    for i in [1...segments.length]
      segment = segments[i]
      segment.length = segment.p.distanceFrom(segments[i - 1].p)
      if 0 == segment.length
        t += segment.dt
      else
        dt = nextDistance / segment.length * segment.dt
        segment.remainingLength = segment.length
        while segment.remainingLength >= nextDistance
          segment.remainingLength -= nextDistance
          t += dt
          times.push(t)
          if distance != nextDistance
            nextDistance = distance
            dt = nextDistance / segment.length * segment.dt
        nextDistance -= segment.remainingLength
        t = segment.tEnd
    return {times: times, nextDistance: nextDistance}

  # Return the coefficients of the polynomials for x and y in t.
  # From Oliver Steele's bezier.js library.
  coefficients: ->
    # @function deals with polynomials, represented as
    # arrays of coefficients.  p[i] is the coefficient of n^i.

    # p0, p1 => p0 + (p1 - p0) * n
    # side-effects (denormalizes) p0, for convienence
    interpolate = (p0, p1) ->
      p0.push(0)
      p = new Array(p0.length)
      p[0] = p0[0]
      for i in [0...p1.length]
        p[i + 1] = p0[i + 1] + p1[i] - p0[i]
      p

    # folds +interpolate+ across a graph whose fringe is
    # the polynomial elements of +ns+, and returns its TOP
    collapse = (ns) ->
      while ns.length > 1
        ps = new Array(ns.length-1)
        for i in [0...(ns.length-1)]
          ps[i] = interpolate(ns[i], ns[i + 1])
        ns = ps
      return ns[0]

    # xps and yps are arrays of polynomials --- concretely realized
    # as arrays of arrays
    xps = []
    yps = []
    for pt in @points
      xps.push([pt.x])
      yps.push([pt.y])
    result = {xs: collapse(xps), ys: collapse(yps)}
    return (@coefficients = ->result)()

  # Return the point at time t.
  # From Oliver Steele's bezier.js library.
  pointAtT: (t) ->
    c = @coefficients()
    [cx, cy] = [c.xs, c.ys]
    # evaluate cx[0] + cx[1]t +cx[2]t^2 ....

    # optimization: start from the end, to save one
    # muliplicate per order (we never need an explicit t^n)

    # optimization: special-case the last element
    # to save a multiply-add
    x = cx[cx.length - 1]; y = cy[cy.length - 1];

    for i in [cx.length..0]
      x = x * t + cx[i]
      y = y * t + cy[i]
    new Point(x, y)

  # Render the Bezier to a WHATWG 2D canvas context.
  # Based on Oliver Steele's bezier.js library.
  makePath: (ctx, moveTo=true) ->
    ctx.moveTo(@points[0].x, @points[0].y) if (moveTo)
    fn = @pathCommands[@order]
    if fn
      coords = []
      for i in [(if 1 == @order then 0 else 1)...@points.length]
        coords.push(@points[i].x)
        coords.push(@points[i].y)
      fn.apply(ctx, coords)

  # Wrapper functions to work around Safari, in which, up to at least 2.0.3,
  # fn.apply isn't defined on the context primitives.
  # Based on Oliver Steele's bezier.js library.
  pathCommands: [
    null,
    # @will have an effect if there's a line thickness or end cap.
    (x, y) -> @lineTo(x + 0.001, y)
    (x, y) -> @lineTo(x, y)
    (x1, y1, x2, y2) -> @quadraticCurveTo(x1, y1, x2, y2)
    (x1, y1, x2, y2, x3, y3) -> @bezierCurveTo(x1, y1, x2, y2, x3, y3)
  ]

  makeDashedPath: (ctx, dashLength, firstDistance, drawFirst=true) ->
    firstDistance = dashLength if !firstDistance
    markedEvery = @markedEvery(dashLength, firstDistance)
    markedEvery.times.unshift(0) if (drawFirst)
    drawLast = (markedEvery.times.length % 2)
    markedEvery.times.push(1) if drawLast
    for i in [1...(markedEvery.times.length)] by 2
      @mid(markedEvery.times[i - 1], markedEvery.times[i]).makePath(ctx)
    return {firstDistance: markedEvery.nextDistance, drawFirst: drawLast}

  makeDottedPath: (ctx, dotSpacing, firstDistance) ->
    firstDistance = dotSpacing if !firstDistance
    markedEvery = @markedEvery(dotSpacing, firstDistance)
    markedEvery.times.unshift(0) if dotSpacing == firstDistance
    for t in markedEvery.times
      @pointAtT(t).makePath(ctx)
    return markedEvery.nextDistance

class Path
  constructor: (@segments=[]) ->

  setupSegments: ->

    # Based on Oliver Steele's bezier.js library.
  addBezier: (pointsOrBezier) ->
    @segments.push(if pointsOrBezier instanceof Array then new Bezier(pointsOrBezier) else pointsOrBezier)

  offset: (dx, dy) ->
    @setupSegments() if 0 == @segments.length
    for segment in @segments
      segment.offset(dx, dy)

  getBB: ->
    @setupSegments() if 0 == @segments.length
    p = @segments[0].points[0]
    l = r = p.x
    t = b = p.y
    for segment in @segments
      for point in segment.points
        l = Math.min(l, point.x)
        t = Math.min(t, point.y)
        r = Math.max(r, point.x)
        b = Math.max(b, point.y)

    rect = new Rect(l, t, r, b);
    return (@getBB = -> rect)()

  isPointInBB: (x, y, tolerance=0) ->
    bb = @getBB()
    if 0 < tolerance
      bb = clone(bb)
      bb.inset(-tolerance, -tolerance)
    return !(x < bb.l || x > bb.r || y < bb.t || y > bb.b)

  isPointOnPath: (x, y, tolerance=0) ->
    return false if !@isPointInBB(x, y, tolerance)
    result = false;
    for segment in @segments
      if segment.isPointOnBezier(x, y, tolerance)
        result = true
        throw $break
    return result

  isPointInPath: (x, y) -> false

  # Based on Oliver Steele's bezier.js library.
  makePath: (ctx) ->
    @setupSegments() if 0 == @segments.length
    moveTo = true
    for segment in @segments
      segment.makePath(ctx, moveTo)
      moveTo = false

  makeDashedPath: (ctx, dashLength, firstDistance, drawFirst) ->
    @setupSegments() if 0 == @segments.length
    info =
      drawFirst: if !drawFirst? then true else drawFirst
      firstDistance: firstDistance || dashLength

    for segment in @segments
      info = segment.makeDashedPath(ctx, dashLength, info.firstDistance, info.drawFirst)

  makeDottedPath: (ctx, dotSpacing, firstDistance) ->
    @setupSegments() if 0 == @segments.length
    firstDistance = dotSpacing if !firstDistance
    for segment in @segments
      firstDistance = segment.makeDottedPath(ctx, dotSpacing, firstDistance)

class Polygon extends Path
  constructor: (@points=[]) -> super()

  setupSegments: ->
    for p, i in @points
      next = i + 1
      next = 0 if @points.length == next
      @addBezier([p, @points[next]])

class Rect extends Polygon
  constructor: (@l, @t, @r, @b) -> super()

  inset: (ix, iy) ->
    @l += ix
    @t += iy
    @r -= ix
    @b -= iy
    return this

  expandToInclude: (rect) ->
    @l = Math.min(@l, rect.l)
    @t = Math.min(@t, rect.t)
    @r = Math.max(@r, rect.r)
    @b = Math.max(@b, rect.b)

  getWidth: -> @r - @l
  getHeight: -> @b - @t

  setupSegments: ->
    w = @getWidth()
    h = @getHeight()
    @points = [
      new Point(@l, @t)
      new Point(@l + w, @t)
      new Point(@l + w, @t + h)
      new Point(@l, @t + h)
    ]
    super()

class Ellipse extends Path
  KAPPA: 0.5522847498,
  constructor: (@cx, @cy, @rx, @ry) -> super()

  setupSegments: ->
    @addBezier([
      new Point(@cx, @cy - @ry)
      new Point(@cx + @KAPPA * @rx, @cy - @ry)
      new Point(@cx + @rx, @cy - @KAPPA * @ry)
      new Point(@cx + @rx, @cy)
    ])
    @addBezier([
      new Point(@cx + @rx, @cy)
      new Point(@cx + @rx, @cy + @KAPPA * @ry)
      new Point(@cx + @KAPPA * @rx, @cy + @ry)
      new Point(@cx, @cy + @ry)
    ])
    @addBezier([
      new Point(@cx, @cy + @ry)
      new Point(@cx - @KAPPA * @rx, @cy + @ry)
      new Point(@cx - @rx, @cy + @KAPPA * @ry)
      new Point(@cx - @rx, @cy)
    ]);
    @addBezier([
      new Point(@cx - @rx, @cy)
      new Point(@cx - @rx, @cy - @KAPPA * @ry)
      new Point(@cx - @KAPPA * @rx, @cy - @ry)
      new Point(@cx, @cy - @ry)
    ])

escapeHTML = (str) ->
  div = document.createElement('div')
  div.appendChild(document.createTextNode(str))
  div.innerHTML

debug = (str) ->
      console.log str

clone = (obj) ->
  if not obj? or typeof obj isnt 'object'
    return obj

  if obj instanceof Date
    return new Date(obj.getTime())

  if obj instanceof RegExp
    flags = ''
    flags += 'g' if obj.global?
    flags += 'i' if obj.ignoreCase?
    flags += 'm' if obj.multiline?
    flags += 'y' if obj.sticky?
    return new RegExp(obj.source, flags)

  newInstance = new obj.constructor()

  for key of obj
    newInstance[key] = clone obj[key]

  return newInstance

#/*
# * This file is part of Canviz. See http://www.canviz.org/
# * $Id: x11colors.js 246 2008-12-27 08:36:24Z ryandesign.com $
# */

Canviz.colors.x11 =
  aliceblue:'f0f8ff'
  antiquewhite:'faebd7'
  antiquewhite1:'ffefdb'
  antiquewhite2:'eedfcc'
  antiquewhite3:'cdc0b0'
  antiquewhite4:'8b8378'
  aquamarine:'7fffd4'
  aquamarine1:'7fffd4'
  aquamarine2:'76eec6'
  aquamarine3:'66cdaa'
  aquamarine4:'458b74'
  azure:'f0ffff'
  azure1:'f0ffff'
  azure2:'e0eeee'
  azure3:'c1cdcd'
  azure4:'838b8b'
  beige:'f5f5dc'
  bisque:'ffe4c4'
  bisque1:'ffe4c4'
  bisque2:'eed5b7'
  bisque3:'cdb79e'
  bisque4:'8b7d6b'
  black:'000000'
  blanchedalmond:'ffebcd'
  blue:'0000ff'
  blue1:'0000ff'
  blue2:'0000ee'
  blue3:'0000cd'
  blue4:'00008b'
  blueviolet:'8a2be2'
  brown:'a52a2a'
  brown1:'ff4040'
  brown2:'ee3b3b'
  brown3:'cd3333'
  brown4:'8b2323'
  burlywood:'deb887'
  burlywood1:'ffd39b'
  burlywood2:'eec591'
  burlywood3:'cdaa7d'
  burlywood4:'8b7355'
  cadetblue:'5f9ea0'
  cadetblue1:'98f5ff'
  cadetblue2:'8ee5ee'
  cadetblue3:'7ac5cd'
  cadetblue4:'53868b'
  chartreuse:'7fff00'
  chartreuse1:'7fff00'
  chartreuse2:'76ee00'
  chartreuse3:'66cd00'
  chartreuse4:'458b00'
  chocolate:'d2691e'
  chocolate1:'ff7f24'
  chocolate2:'ee7621'
  chocolate3:'cd661d'
  chocolate4:'8b4513'
  coral:'ff7f50'
  coral1:'ff7256'
  coral2:'ee6a50'
  coral3:'cd5b45'
  coral4:'8b3e2f'
  cornflowerblue:'6495ed'
  cornsilk:'fff8dc'
  cornsilk1:'fff8dc'
  cornsilk2:'eee8cd'
  cornsilk3:'cdc8b1'
  cornsilk4:'8b8878'
  crimson:'dc143c'
  cyan:'00ffff'
  cyan1:'00ffff'
  cyan2:'00eeee'
  cyan3:'00cdcd'
  cyan4:'008b8b'
  darkgoldenrod:'b8860b'
  darkgoldenrod1:'ffb90f'
  darkgoldenrod2:'eead0e'
  darkgoldenrod3:'cd950c'
  darkgoldenrod4:'8b6508'
  darkgreen:'006400'
  darkkhaki:'bdb76b'
  darkolivegreen:'556b2f'
  darkolivegreen1:'caff70'
  darkolivegreen2:'bcee68'
  darkolivegreen3:'a2cd5a'
  darkolivegreen4:'6e8b3d'
  darkorange:'ff8c00'
  darkorange1:'ff7f00'
  darkorange2:'ee7600'
  darkorange3:'cd6600'
  darkorange4:'8b4500'
  darkorchid:'9932cc'
  darkorchid1:'bf3eff'
  darkorchid2:'b23aee'
  darkorchid3:'9a32cd'
  darkorchid4:'68228b'
  darksalmon:'e9967a'
  darkseagreen:'8fbc8f'
  darkseagreen1:'c1ffc1'
  darkseagreen2:'b4eeb4'
  darkseagreen3:'9bcd9b'
  darkseagreen4:'698b69'
  darkslateblue:'483d8b'
  darkslategray:'2f4f4f'
  darkslategray1:'97ffff'
  darkslategray2:'8deeee'
  darkslategray3:'79cdcd'
  darkslategray4:'528b8b'
  darkslategrey:'2f4f4f'
  darkturquoise:'00ced1'
  darkviolet:'9400d3'
  deeppink:'ff1493'
  deeppink1:'ff1493'
  deeppink2:'ee1289'
  deeppink3:'cd1076'
  deeppink4:'8b0a50'
  deepskyblue:'00bfff'
  deepskyblue1:'00bfff'
  deepskyblue2:'00b2ee'
  deepskyblue3:'009acd'
  deepskyblue4:'00688b'
  dimgray:'696969'
  dimgrey:'696969'
  dodgerblue:'1e90ff'
  dodgerblue1:'1e90ff'
  dodgerblue2:'1c86ee'
  dodgerblue3:'1874cd'
  dodgerblue4:'104e8b'
  firebrick:'b22222'
  firebrick1:'ff3030'
  firebrick2:'ee2c2c'
  firebrick3:'cd2626'
  firebrick4:'8b1a1a'
  floralwhite:'fffaf0'
  forestgreen:'228b22'
  gainsboro:'dcdcdc'
  ghostwhite:'f8f8ff'
  gold:'ffd700'
  gold1:'ffd700'
  gold2:'eec900'
  gold3:'cdad00'
  gold4:'8b7500'
  goldenrod:'daa520'
  goldenrod1:'ffc125'
  goldenrod2:'eeb422'
  goldenrod3:'cd9b1d'
  goldenrod4:'8b6914'
  gray:'c0c0c0'
  gray0:'000000'
  gray1:'030303'
  gray10:'1a1a1a'
  gray100:'ffffff'
  gray11:'1c1c1c'
  gray12:'1f1f1f'
  gray13:'212121'
  gray14:'242424'
  gray15:'262626'
  gray16:'292929'
  gray17:'2b2b2b'
  gray18:'2e2e2e'
  gray19:'303030'
  gray2:'050505'
  gray20:'333333'
  gray21:'363636'
  gray22:'383838'
  gray23:'3b3b3b'
  gray24:'3d3d3d'
  gray25:'404040'
  gray26:'424242'
  gray27:'454545'
  gray28:'474747'
  gray29:'4a4a4a'
  gray3:'080808'
  gray30:'4d4d4d'
  gray31:'4f4f4f'
  gray32:'525252'
  gray33:'545454'
  gray34:'575757'
  gray35:'595959'
  gray36:'5c5c5c'
  gray37:'5e5e5e'
  gray38:'616161'
  gray39:'636363'
  gray4:'0a0a0a'
  gray40:'666666'
  gray41:'696969'
  gray42:'6b6b6b'
  gray43:'6e6e6e'
  gray44:'707070'
  gray45:'737373'
  gray46:'757575'
  gray47:'787878'
  gray48:'7a7a7a'
  gray49:'7d7d7d'
  gray5:'0d0d0d'
  gray50:'7f7f7f'
  gray51:'828282'
  gray52:'858585'
  gray53:'878787'
  gray54:'8a8a8a'
  gray55:'8c8c8c'
  gray56:'8f8f8f'
  gray57:'919191'
  gray58:'949494'
  gray59:'969696'
  gray6:'0f0f0f'
  gray60:'999999'
  gray61:'9c9c9c'
  gray62:'9e9e9e'
  gray63:'a1a1a1'
  gray64:'a3a3a3'
  gray65:'a6a6a6'
  gray66:'a8a8a8'
  gray67:'ababab'
  gray68:'adadad'
  gray69:'b0b0b0'
  gray7:'121212'
  gray70:'b3b3b3'
  gray71:'b5b5b5'
  gray72:'b8b8b8'
  gray73:'bababa'
  gray74:'bdbdbd'
  gray75:'bfbfbf'
  gray76:'c2c2c2'
  gray77:'c4c4c4'
  gray78:'c7c7c7'
  gray79:'c9c9c9'
  gray8:'141414'
  gray80:'cccccc'
  gray81:'cfcfcf'
  gray82:'d1d1d1'
  gray83:'d4d4d4'
  gray84:'d6d6d6'
  gray85:'d9d9d9'
  gray86:'dbdbdb'
  gray87:'dedede'
  gray88:'e0e0e0'
  gray89:'e3e3e3'
  gray9:'171717'
  gray90:'e5e5e5'
  gray91:'e8e8e8'
  gray92:'ebebeb'
  gray93:'ededed'
  gray94:'f0f0f0'
  gray95:'f2f2f2'
  gray96:'f5f5f5'
  gray97:'f7f7f7'
  gray98:'fafafa'
  gray99:'fcfcfc'
  green:'00ff00'
  green1:'00ff00'
  green2:'00ee00'
  green3:'00cd00'
  green4:'008b00'
  greenyellow:'adff2f'
  grey:'c0c0c0'
  grey0:'000000'
  grey1:'030303'
  grey10:'1a1a1a'
  grey100:'ffffff'
  grey11:'1c1c1c'
  grey12:'1f1f1f'
  grey13:'212121'
  grey14:'242424'
  grey15:'262626'
  grey16:'292929'
  grey17:'2b2b2b'
  grey18:'2e2e2e'
  grey19:'303030'
  grey2:'050505'
  grey20:'333333'
  grey21:'363636'
  grey22:'383838'
  grey23:'3b3b3b'
  grey24:'3d3d3d'
  grey25:'404040'
  grey26:'424242'
  grey27:'454545'
  grey28:'474747'
  grey29:'4a4a4a'
  grey3:'080808'
  grey30:'4d4d4d'
  grey31:'4f4f4f'
  grey32:'525252'
  grey33:'545454'
  grey34:'575757'
  grey35:'595959'
  grey36:'5c5c5c'
  grey37:'5e5e5e'
  grey38:'616161'
  grey39:'636363'
  grey4:'0a0a0a'
  grey40:'666666'
  grey41:'696969'
  grey42:'6b6b6b'
  grey43:'6e6e6e'
  grey44:'707070'
  grey45:'737373'
  grey46:'757575'
  grey47:'787878'
  grey48:'7a7a7a'
  grey49:'7d7d7d'
  grey5:'0d0d0d'
  grey50:'7f7f7f'
  grey51:'828282'
  grey52:'858585'
  grey53:'878787'
  grey54:'8a8a8a'
  grey55:'8c8c8c'
  grey56:'8f8f8f'
  grey57:'919191'
  grey58:'949494'
  grey59:'969696'
  grey6:'0f0f0f'
  grey60:'999999'
  grey61:'9c9c9c'
  grey62:'9e9e9e'
  grey63:'a1a1a1'
  grey64:'a3a3a3'
  grey65:'a6a6a6'
  grey66:'a8a8a8'
  grey67:'ababab'
  grey68:'adadad'
  grey69:'b0b0b0'
  grey7:'121212'
  grey70:'b3b3b3'
  grey71:'b5b5b5'
  grey72:'b8b8b8'
  grey73:'bababa'
  grey74:'bdbdbd'
  grey75:'bfbfbf'
  grey76:'c2c2c2'
  grey77:'c4c4c4'
  grey78:'c7c7c7'
  grey79:'c9c9c9'
  grey8:'141414'
  grey80:'cccccc'
  grey81:'cfcfcf'
  grey82:'d1d1d1'
  grey83:'d4d4d4'
  grey84:'d6d6d6'
  grey85:'d9d9d9'
  grey86:'dbdbdb'
  grey87:'dedede'
  grey88:'e0e0e0'
  grey89:'e3e3e3'
  grey9:'171717'
  grey90:'e5e5e5'
  grey91:'e8e8e8'
  grey92:'ebebeb'
  grey93:'ededed'
  grey94:'f0f0f0'
  grey95:'f2f2f2'
  grey96:'f5f5f5'
  grey97:'f7f7f7'
  grey98:'fafafa'
  grey99:'fcfcfc'
  honeydew:'f0fff0'
  honeydew1:'f0fff0'
  honeydew2:'e0eee0'
  honeydew3:'c1cdc1'
  honeydew4:'838b83'
  hotpink:'ff69b4'
  hotpink1:'ff6eb4'
  hotpink2:'ee6aa7'
  hotpink3:'cd6090'
  hotpink4:'8b3a62'
  indianred:'cd5c5c'
  indianred1:'ff6a6a'
  indianred2:'ee6363'
  indianred3:'cd5555'
  indianred4:'8b3a3a'
  indigo:'4b0082'
  invis:'fffffe00'
  ivory:'fffff0'
  ivory1:'fffff0'
  ivory2:'eeeee0'
  ivory3:'cdcdc1'
  ivory4:'8b8b83'
  khaki:'f0e68c'
  khaki1:'fff68f'
  khaki2:'eee685'
  khaki3:'cdc673'
  khaki4:'8b864e'
  lavender:'e6e6fa'
  lavenderblush:'fff0f5'
  lavenderblush1:'fff0f5'
  lavenderblush2:'eee0e5'
  lavenderblush3:'cdc1c5'
  lavenderblush4:'8b8386'
  lawngreen:'7cfc00'
  lemonchiffon:'fffacd'
  lemonchiffon1:'fffacd'
  lemonchiffon2:'eee9bf'
  lemonchiffon3:'cdc9a5'
  lemonchiffon4:'8b8970'
  lightblue:'add8e6'
  lightblue1:'bfefff'
  lightblue2:'b2dfee'
  lightblue3:'9ac0cd'
  lightblue4:'68838b'
  lightcoral:'f08080'
  lightcyan:'e0ffff'
  lightcyan1:'e0ffff'
  lightcyan2:'d1eeee'
  lightcyan3:'b4cdcd'
  lightcyan4:'7a8b8b'
  lightgoldenrod:'eedd82'
  lightgoldenrod1:'ffec8b'
  lightgoldenrod2:'eedc82'
  lightgoldenrod3:'cdbe70'
  lightgoldenrod4:'8b814c'
  lightgoldenrodyellow:'fafad2'
  lightgray:'d3d3d3'
  lightgrey:'d3d3d3'
  lightpink:'ffb6c1'
  lightpink1:'ffaeb9'
  lightpink2:'eea2ad'
  lightpink3:'cd8c95'
  lightpink4:'8b5f65'
  lightsalmon:'ffa07a'
  lightsalmon1:'ffa07a'
  lightsalmon2:'ee9572'
  lightsalmon3:'cd8162'
  lightsalmon4:'8b5742'
  lightseagreen:'20b2aa'
  lightskyblue:'87cefa'
  lightskyblue1:'b0e2ff'
  lightskyblue2:'a4d3ee'
  lightskyblue3:'8db6cd'
  lightskyblue4:'607b8b'
  lightslateblue:'8470ff'
  lightslategray:'778899'
  lightslategrey:'778899'
  lightsteelblue:'b0c4de'
  lightsteelblue1:'cae1ff'
  lightsteelblue2:'bcd2ee'
  lightsteelblue3:'a2b5cd'
  lightsteelblue4:'6e7b8b'
  lightyellow:'ffffe0'
  lightyellow1:'ffffe0'
  lightyellow2:'eeeed1'
  lightyellow3:'cdcdb4'
  lightyellow4:'8b8b7a'
  limegreen:'32cd32'
  linen:'faf0e6'
  magenta:'ff00ff'
  magenta1:'ff00ff'
  magenta2:'ee00ee'
  magenta3:'cd00cd'
  magenta4:'8b008b'
  maroon:'b03060'
  maroon1:'ff34b3'
  maroon2:'ee30a7'
  maroon3:'cd2990'
  maroon4:'8b1c62'
  mediumaquamarine:'66cdaa'
  mediumblue:'0000cd'
  mediumorchid:'ba55d3'
  mediumorchid1:'e066ff'
  mediumorchid2:'d15fee'
  mediumorchid3:'b452cd'
  mediumorchid4:'7a378b'
  mediumpurple:'9370db'
  mediumpurple1:'ab82ff'
  mediumpurple2:'9f79ee'
  mediumpurple3:'8968cd'
  mediumpurple4:'5d478b'
  mediumseagreen:'3cb371'
  mediumslateblue:'7b68ee'
  mediumspringgreen:'00fa9a'
  mediumturquoise:'48d1cc'
  mediumvioletred:'c71585'
  midnightblue:'191970'
  mintcream:'f5fffa'
  mistyrose:'ffe4e1'
  mistyrose1:'ffe4e1'
  mistyrose2:'eed5d2'
  mistyrose3:'cdb7b5'
  mistyrose4:'8b7d7b'
  moccasin:'ffe4b5'
  navajowhite:'ffdead'
  navajowhite1:'ffdead'
  navajowhite2:'eecfa1'
  navajowhite3:'cdb38b'
  navajowhite4:'8b795e'
  navy:'000080'
  navyblue:'000080'
  none:'fffffe00'
  oldlace:'fdf5e6'
  olivedrab:'6b8e23'
  olivedrab1:'c0ff3e'
  olivedrab2:'b3ee3a'
  olivedrab3:'9acd32'
  olivedrab4:'698b22'
  orange:'ffa500'
  orange1:'ffa500'
  orange2:'ee9a00'
  orange3:'cd8500'
  orange4:'8b5a00'
  orangered:'ff4500'
  orangered1:'ff4500'
  orangered2:'ee4000'
  orangered3:'cd3700'
  orangered4:'8b2500'
  orchid:'da70d6'
  orchid1:'ff83fa'
  orchid2:'ee7ae9'
  orchid3:'cd69c9'
  orchid4:'8b4789'
  palegoldenrod:'eee8aa'
  palegreen:'98fb98'
  palegreen1:'9aff9a'
  palegreen2:'90ee90'
  palegreen3:'7ccd7c'
  palegreen4:'548b54'
  paleturquoise:'afeeee'
  paleturquoise1:'bbffff'
  paleturquoise2:'aeeeee'
  paleturquoise3:'96cdcd'
  paleturquoise4:'668b8b'
  palevioletred:'db7093'
  palevioletred1:'ff82ab'
  palevioletred2:'ee799f'
  palevioletred3:'cd6889'
  palevioletred4:'8b475d'
  papayawhip:'ffefd5'
  peachpuff:'ffdab9'
  peachpuff1:'ffdab9'
  peachpuff2:'eecbad'
  peachpuff3:'cdaf95'
  peachpuff4:'8b7765'
  peru:'cd853f'
  pink:'ffc0cb'
  pink1:'ffb5c5'
  pink2:'eea9b8'
  pink3:'cd919e'
  pink4:'8b636c'
  plum:'dda0dd'
  plum1:'ffbbff'
  plum2:'eeaeee'
  plum3:'cd96cd'
  plum4:'8b668b'
  powderblue:'b0e0e6'
  purple:'a020f0'
  purple1:'9b30ff'
  purple2:'912cee'
  purple3:'7d26cd'
  purple4:'551a8b'
  red:'ff0000'
  red1:'ff0000'
  red2:'ee0000'
  red3:'cd0000'
  red4:'8b0000'
  rosybrown:'bc8f8f'
  rosybrown1:'ffc1c1'
  rosybrown2:'eeb4b4'
  rosybrown3:'cd9b9b'
  rosybrown4:'8b6969'
  royalblue:'4169e1'
  royalblue1:'4876ff'
  royalblue2:'436eee'
  royalblue3:'3a5fcd'
  royalblue4:'27408b'
  saddlebrown:'8b4513'
  salmon:'fa8072'
  salmon1:'ff8c69'
  salmon2:'ee8262'
  salmon3:'cd7054'
  salmon4:'8b4c39'
  sandybrown:'f4a460'
  seagreen:'2e8b57'
  seagreen1:'54ff9f'
  seagreen2:'4eee94'
  seagreen3:'43cd80'
  seagreen4:'2e8b57'
  seashell:'fff5ee'
  seashell1:'fff5ee'
  seashell2:'eee5de'
  seashell3:'cdc5bf'
  seashell4:'8b8682'
  sienna:'a0522d'
  sienna1:'ff8247'
  sienna2:'ee7942'
  sienna3:'cd6839'
  sienna4:'8b4726'
  skyblue:'87ceeb'
  skyblue1:'87ceff'
  skyblue2:'7ec0ee'
  skyblue3:'6ca6cd'
  skyblue4:'4a708b'
  slateblue:'6a5acd'
  slateblue1:'836fff'
  slateblue2:'7a67ee'
  slateblue3:'6959cd'
  slateblue4:'473c8b'
  slategray:'708090'
  slategray1:'c6e2ff'
  slategray2:'b9d3ee'
  slategray3:'9fb6cd'
  slategray4:'6c7b8b'
  slategrey:'708090'
  snow:'fffafa'
  snow1:'fffafa'
  snow2:'eee9e9'
  snow3:'cdc9c9'
  snow4:'8b8989'
  springgreen:'00ff7f'
  springgreen1:'00ff7f'
  springgreen2:'00ee76'
  springgreen3:'00cd66'
  springgreen4:'008b45'
  steelblue:'4682b4'
  steelblue1:'63b8ff'
  steelblue2:'5cacee'
  steelblue3:'4f94cd'
  steelblue4:'36648b'
  tan:'d2b48c'
  tan1:'ffa54f'
  tan2:'ee9a49'
  tan3:'cd853f'
  tan4:'8b5a2b'
  thistle:'d8bfd8'
  thistle1:'ffe1ff'
  thistle2:'eed2ee'
  thistle3:'cdb5cd'
  thistle4:'8b7b8b'
  tomato:'ff6347'
  tomato1:'ff6347'
  tomato2:'ee5c42'
  tomato3:'cd4f39'
  tomato4:'8b3626'
  transparent:'fffffe00'
  turquoise:'40e0d0'
  turquoise1:'00f5ff'
  turquoise2:'00e5ee'
  turquoise3:'00c5cd'
  turquoise4:'00868b'
  violet:'ee82ee'
  violetred:'d02090'
  violetred1:'ff3e96'
  violetred2:'ee3a8c'
  violetred3:'cd3278'
  violetred4:'8b2252'
  wheat:'f5deb3'
  wheat1:'ffe7ba'
  wheat2:'eed8ae'
  wheat3:'cdba96'
  wheat4:'8b7e66'
  white:'ffffff'
  whitesmoke:'f5f5f5'
  yellow:'ffff00'
  yellow1:'ffff00'
  yellow2:'eeee00'
  yellow3:'cdcd00'
  yellow4:'8b8b00'
  yellowgreen:'9acd32'


window.Canviz = Canviz
