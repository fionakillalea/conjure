import * as React from "react"
import StageHeader from "./StageHeader"
import { Check } from "./Check"
import Play from "./Play"

interface Props {
  reverse: boolean
  playing: boolean
  collapseAsExploring: boolean
  collapseAsExploringHandler: () => void
  reverseChangeHandler: () => void
  pPressedHandler: () => void
}

interface State {}

class PlaySettings extends React.Component<Props, State> {
  constructor(props: any) {
    super(props)
    this.state = {}
  }

  render = () => {
    return (
      <StageHeader title="Play Settings" id="playSettings" isCollapsed={false}>
        <div className=" row">
          <div className="player mb-3 col-2">
            <Play
              clickHandler={this.props.pPressedHandler}
              playing={this.props.playing}
              x={0}
            />
          </div>

          <div className="col-10">
            <Check
              title={"Reverse"}
              checked={this.props.reverse}
              onChange={this.props.reverseChangeHandler}
            />

            <Check
              title={"Collapse explored failed branches when playing"}
              checked={this.props.collapseAsExploring}
              onChange={this.props.collapseAsExploringHandler}
            />
          </div>
        </div>
      </StageHeader>
    )
  }
}

export default PlaySettings
