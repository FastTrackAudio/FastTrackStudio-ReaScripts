import React from "react"
import "./App.css"
import ReaperInterface from "./ReaperInterface"

function App() {
  return (
    <div className="App">
      <header className="App-header">
        <h1>React Reaper UI</h1>
        <p>A modern TypeScript and React interface for REAPER</p>
      </header>
      <main>
        <ReaperInterface title="REAPER Control Panel" />
      </main>
      <footer>
        <p>Built with React and TypeScript</p>
      </footer>
    </div>
  )
}

export default App
