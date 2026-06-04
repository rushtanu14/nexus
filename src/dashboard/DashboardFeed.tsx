type EchoAction = {
  id: string;
  pet?: string;
  provider?: string;
  title: string;
  summary: string;
  status: "pending" | "running" | "done" | "error" | "canceled" | string;
  source_quote?: string;
};

export function DashboardFeed({
  actions,
  onDispatch,
  onCancel
}: {
  actions: EchoAction[];
  onDispatch?: (action: EchoAction) => void;
  onCancel?: (action: EchoAction) => void;
}) {
  return (
    <section className="nex-echo-dashboard-feed" aria-label="Nex Echo live action feed">
      {actions.map((action) => (
        <article className="nex-echo-action-card" data-status={action.status} key={action.id}>
          <header>
            <strong>{action.pet ?? action.provider ?? "mcp"}</strong>
            <span>{action.status}</span>
          </header>
          <h3>{action.title}</h3>
          <p>{action.summary}</p>
          {action.source_quote ? (
            <details>
              <summary>source quote</summary>
              <p>{action.source_quote}</p>
            </details>
          ) : null}
          <footer>
            <button disabled={action.status === "running"} onClick={() => onDispatch?.(action)}>dispatch</button>
            <button disabled={action.status === "done" || action.status === "canceled"} onClick={() => onCancel?.(action)}>cancel</button>
          </footer>
        </article>
      ))}
    </section>
  );
}
