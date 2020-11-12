
const grid = [
  [ '1', '2', '3', '4', '5', '6', '7', /* '8' */ ],
  [ 'q', 'w', 'e', 'r', 't', 'y', 'u', /* 'i' */ ],
  [ 'a', 's', 'd', 'f', 'g', 'h', 'j', /* 'k' */ ],
  [ 'z', 'x', 'c', 'v', 'b', 'n', 'm', /* ',' */ ]
]

// these are fixed-pixel "functional margins",
// changing the size of the final row and column
// (and hypothetically the first, but that's unimplemented)
const screenMargins = {
  bottom: 185,
  right: 375,
}

const sm = screenMargins

const horizontalMargin = (sm.right || 0) + (sm.left || 0);
const verticalMargin = (sm.top || 0) + (sm.bottom || 0);

const ROWS = grid.length - (sm.bottom ? 1 : 0) - (sm.top ? 1 : 0)
const COLUMNS = grid[0].length - (sm.left ? 1 : 0) - (sm.right ? 1 : 0)

function dimensions(direction, size, margin) {
  const dSize = `screenSize${direction}`
  return `(${dSize} - ${margin}) / ${size}`
}

const rowHeight = dimensions('Y', ROWS, verticalMargin)
const columnWidth = dimensions('X', COLUMNS, horizontalMargin)

function coordinates({ row, column }){
  return {
    x: `${sm.left || 0} + ${column} * ${columnWidth}`,
    y: `${sm.top || 0} + ${row} * ${rowHeight} + 22`
      //  22 is the menu
  }
}

function size(start, end){
  var columns = 1 + end.column - start.column
  var rows = 1 + end.row - start.row
  // last column / row
  var colMarg = (end.column == COLUMNS) ? `- (${columnWidth} - ${sm.right})` : ''
  var rowMarg = (end.row == ROWS) ? `- (${rowHeight} - ${sm.bottom})` : ''
  return {
    width: columns.toString() + " * " + columnWidth + colMarg,
    height: rows.toString() + " * " + rowHeight + rowMarg,
  }
}

function operation(from, to){
  return slate.operation("move", {
    ...coordinates(from),
    ...size(from, to),
  })
}

function hotkey(a, b){
  return `${b}:${a},alt,shift`
}
function binding({ character: a }, { character: b }, op){
  slate.bind(hotkey(a, b), op)
  slate.bind(hotkey(b, a), op)
}
function defineOption(start, end){
  binding(start, end, operation(start, end))
}

function fullWithMargin({ top = 0, bottom = 0, left = 0, right = 0 } = {}){
  return operation(
    { row: 0 + top , column: 0 + left },
    { row: ROWS - 1 - bottom, column: COLUMNS - 1 - right },
  )
}

function singletons({ 
  paddedFull,
  full,
  upperLeft,
  upperRight,
  upperLarge,
  lowerLarge,
}){

  slate.bind(`${paddedFull}:alt,shift`, fullWithMargin())

  slate.bind(`${upperLarge}:alt,shift`, fullWithMargin({
    top: 0,
    left: 0,
    bottom: 1,
    right: 2,
  }))


  // todo big left and right seem like sane patterns
  slate.bind(`${upperLeft}:alt,shift`, fullWithMargin({
    top: 0,
    left: 0,
    bottom: 1,
    right: COLUMNS - 2,
  }))

  // Typical central area
  slate.bind(`${upperRight}:alt,shift`, fullWithMargin({
    top: 0,
    left: COLUMNS - 4,
    bottom: 1,
    right: 2,
  }))

  
  // True fullscreen
  slate.bind(`${full}:alt,shift`, fullWithMargin({
    bottom: -1,
    right: -1,
  }))

  // Large bottom window that goes beyond bounds
  slate.bind(`${lowerLarge}:alt,shift`, fullWithMargin({
    top: 1,
    left: 0,
    bottom: -1,
    right: 2,
  }))


}

function defineSubGrid(start){
  grid
    .forEach((rowArr, row) => {
      if(row >= start.row){
        rowArr.forEach((character, column) => {
          if(column >= start.column){
            defineOption(start, { character, row, column })
          }
        })
      }
    })
}

grid.forEach((rowArr, row) => {
  rowArr.forEach((character, column) => {
    slate.bind(hotkey(character, 'esc'), function(){});
    defineSubGrid({ character, row, column })
  })
})

singletons({
  paddedFull: "-",
  full: "=",
  upperLeft: "[",
  upperRight: "]",
  upperLarge: "'",
  lowerLarge: "/",
})


slate.bindAll({
  'h:ctrl,shift': slate.operation('focus', { direction: 'left' }),
  'l:ctrl,shift': slate.operation('focus', { direction: 'right' }),
  'k:ctrl,shift': slate.operation('focus', { direction: 'up' }),
  'j:ctrl,shift': slate.operation('focus', { direction: 'down' }),

  'a:cmd,shift': slate.operation('focus', { direction: 'left' }),
  'd:cmd,shift': slate.operation('focus', { direction: 'right' }),
  'w:cmd,shift': slate.operation('focus', { direction: 'up' }),
  's:cmd,shift': slate.operation('focus', { direction: 'down' }),
})
