import { HierarchyPointNode } from "d3"
import * as d3 from "d3"
import Node from "./Node"
import * as TreeHelper from "./TreeHelper"
import { State, MyMap, Core, TreeContainer } from "../components/TreeContainer"
import { cloneDeep, last, min, max } from "lodash"
import { Collapse } from "react-select/lib/animated/transitions"
import { headers } from "./Helper"

export const nextSol = (instance: TreeContainer) => {
  instance.setState((prevState: State) => {
    const solId = TreeHelper.getNextSolId(prevState)

    if (solId === -1) {
      return null
    }

    const newMap = TreeHelper.showAllAncestors(prevState, solId)
    return { selected: solId, id2Node: newMap }
  })
}
export const nextFailed = (instance: TreeContainer) => {
  if (!instance.state.solveable) {
    goLeft(instance)
    return
  }

  if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
    let nextId = TreeHelper.getNextFailedId(
      instance.state.selected,
      instance.props.core.solAncestorIds
    )
    if (nextId !== -1) {
      instance.setState((prevState: State) => {
        const newMap = TreeHelper.showAllAncestors(prevState, nextId)
        return { selected: nextId, id2Node: newMap }
      })
    }
    return
  }

  if (
    instance.props.core.solAncestorIds.includes(instance.state.selected + 1)
  ) {
    let nextId = TreeHelper.getNextFailedId(
      instance.state.selected + 1,
      instance.props.core.solAncestorIds
    )
    if (nextId !== -1) {
      instance.setState((prevState: State) => {
        const newMap = TreeHelper.showAllAncestors(prevState, nextId)
        return { selected: nextId, id2Node: newMap }
      })
    }
  } else {
    goLeft(instance)
  }
}

export const prevFailed = (instance: TreeContainer) => {
  if (!instance.state.solveable) {
    goToPreviousHandler(instance)
    return
  }

  if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
    let nextId = TreeHelper.getPrevFailedId(
      instance.state.selected,
      instance.props.core.solAncestorIds
    )

    if (nextId in instance.state.id2Node) {
      instance.setState((prevState: State) => {
        const newMap = TreeHelper.showAllAncestors(prevState, nextId)
        return { selected: nextId, id2Node: newMap }
      })
    } else {
      goPrev(instance, nextId + 1)
    }
    return
  }

  if (
    instance.props.core.solAncestorIds.includes(instance.state.selected - 1)
  ) {
    let nextId = TreeHelper.getPrevFailedId(
      instance.state.selected - 1,
      instance.props.core.solAncestorIds
    )

    if (nextId === -1) {
      return
    }

    if (nextId in instance.state.id2Node) {
      instance.setState((prevState: State) => {
        const newMap = TreeHelper.showAllAncestors(prevState, nextId)
        return { selected: nextId, id2Node: newMap }
      })
    } else {
      goPrev(instance, nextId + 1)
    }
  } else {
    goPrev(instance)
  }
}

export const prevSol = (instance: TreeContainer) => {
  instance.setState((prevState: State) => {
    const solId = TreeHelper.getPrevSolId(prevState)

    if (solId === -1) {
      return null
    }

    const newMap = TreeHelper.showAllAncestors(prevState, solId)
    return { selected: solId, id2Node: newMap }
  })
}

export const goRight = (instance: TreeContainer) => {
  instance.setState((prev: State) => {
    const current = prev.id2Node[prev.selected]
    if (!current.children) {
      return null
    }
    if (current.children.length < 2) {
      return null
    }
    return { selected: current.children[1].id }
  })
}

export const goUp = (instance: TreeContainer) => {
  instance.setState((prev: State) => {
    const current = prev.id2Node[prev.selected]
    if (current.parentId === -1) {
      return null
    }
    return { selected: current.parentId }
  })
}

export const goLeft = async (instance: TreeContainer) => {
  const nextId = instance.state.selected + 1

  const parent = instance.state.id2Node[nextId]

  const grandParent = parent
    ? instance.state.id2Node[parent.parentId]
    : undefined

  if (nextId in instance.state.id2Node) {
    instance.setState((prevState: State) => {
      const newMap = TreeHelper.showAllAncestors(
        prevState,
        instance.state.selected
      )

      if (
        instance.props.collapseAsExploring &&
        grandParent &&
        grandParent.children &&
        nextId !== grandParent.children![0].id
      ) {
        Node.collapseNode(newMap[grandParent.children![0].id])
      }

      return { selected: nextId, id2Node: newMap }
    })

    return
  }

  const payload = {
    path: instance.props.path,
    nodeId: instance.state.selected,
    depth: instance.props.loadDepth
  }

  await fetch(`http://localhost:${instance.props.nimServerPort}/loadNodes`, {
    method: "post",
    headers: headers,
    body: JSON.stringify(payload)
  })
    .then(data => data.json())
    .then(nodes =>
      TreeHelper.insertNodes(nodes, instance.state.selected, instance)
    )
}

export const goPrev = (instance: TreeContainer, start?: number) => {
  let current = start ? start : instance.state.selected

  if (current === 0) {
    return
  }

  const nextId = current - 1

  if (nextId in instance.state.id2Node) {
    instance.setState((prevState: State) => {
      const newMap = TreeHelper.showAllAncestors(prevState, nextId)
      return { selected: nextId, id2Node: newMap }
    })
    return
  }

  loadAncestors(instance.props.path, nextId, instance)
  // const payload = {
  //   path: instance.props.path,
  //   nodeId: nextId
  // }

  // fetch(`http://localhost:${instance.props.nimServerPort}/loadAncestors`, {
  //   method: "post",
  //   headers: headers,
  //   body: JSON.stringify(payload)
  // })
  //   .then(data => data.json())
  //   .then(nodes => TreeHelper.insertNodes(nodes, nextId, instance))
}

export const loadAncestors = (
  path: string,
  nextId: number,
  instance: TreeContainer
) => {
  // if (nextId in instance.state.id2Node) {
  //   instance.setState((prevState: State) => {
  //     return { id2Node: TreeHelper.showAllAncestors(prevState, nextId) }
  //   })
  //   return
  // }

  const payload = {
    path: path,
    nodeId: nextId
  }

  fetch(`http://localhost:${instance.props.nimServerPort}/loadAncestors`, {
    method: "post",
    headers: headers,
    body: JSON.stringify(payload)
  })
    .then(data => data.json())
    .then(nodes => TreeHelper.insertNodes(nodes, nextId, instance))
}

export const nextSolBranch = (instance: TreeContainer) => {
  if (!instance.state.solveable) {
    return
  }

  if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
    const currentIndex = instance.props.core.solAncestorIds.indexOf(
      instance.state.selected
    )
    if (currentIndex + 1 < instance.props.core.solAncestorIds.length) {
      instance.setState((prevState: State) => {
        const newMap = TreeHelper.showAllAncestors(
          prevState,
          instance.props.core.solAncestorIds[currentIndex + 1]
        )
        return {
          selected: instance.props.core.solAncestorIds[currentIndex + 1],
          id2Node: newMap
        }
      })
    }
    return
  }

  const nextId = min(
    instance.props.core.solAncestorIds.filter(num => {
      return instance.state.selected < num
    })
  )

  if (!nextId) {
    return
  }

  instance.setState((prevState: State) => {
    const newMap = TreeHelper.showAllAncestors(prevState, nextId)
    return {
      selected: nextId,
      id2Node: newMap
    }
  })
}

export const prevSolBranch = (instance: TreeContainer) => {
  if (!instance.state.solveable) {
    return
  }

  if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
    const currentIndex = instance.props.core.solAncestorIds.indexOf(
      instance.state.selected
    )
    if (currentIndex - 1 >= 0) {
      instance.setState((prevState: State) => {
        const newMap = TreeHelper.showAllAncestors(
          prevState,
          instance.props.core.solAncestorIds[currentIndex - 1]
        )
        return {
          selected: instance.props.core.solAncestorIds[currentIndex - 1],
          id2Node: newMap
        }
      })
    }
    return
  }

  const nextId = max(
    instance.props.core.solAncestorIds.filter(num => {
      return instance.state.selected > num
    })
  )

  if (!nextId) {
    return
  }

  instance.setState((prevState: State) => {
    const newMap = TreeHelper.showAllAncestors(prevState, nextId)
    return {
      selected: nextId,
      id2Node: newMap
    }
  })
}

export const goToPreviousHandler = (instance: TreeContainer) => {
  goPrev(instance)
  if (instance.props.collapseAsExploring) {
    instance.collapse()
  }
}
