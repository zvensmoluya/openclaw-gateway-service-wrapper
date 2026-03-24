using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace OpenClaw.Agent.Host;

internal sealed class SessionNotificationPump : IDisposable
{
    private readonly Action _onSessionEnding;
    private Thread? _thread;
    private HiddenSessionWindow? _window;

    public SessionNotificationPump(Action onSessionEnding)
    {
        _onSessionEnding = onSessionEnding;
    }

    public void Start()
    {
        _thread = new Thread(ThreadMain)
        {
            IsBackground = true,
            Name = "OpenClaw.Agent.Host.SessionPump"
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
    }

    public void Dispose()
    {
        if (_window is not null && _window.IsHandleCreated)
        {
            try
            {
                _window.BeginInvoke(() => _window.Close());
            }
            catch
            {
            }
        }
    }

    private void ThreadMain()
    {
        using var form = new HiddenSessionWindow(_onSessionEnding);
        _window = form;
        _ = form.Handle;
        Application.Run(form);
    }

    private sealed class HiddenSessionWindow : Form
    {
        private const int WmQueryEndSession = 0x0011;
        private const int WmEndSession = 0x0016;
        private const int WmWtsSessionChange = 0x02B1;
        private const int WtsSessionLogoff = 0x6;
        private const int NotIfyForThisSession = 0;

        private readonly Action _onSessionEnding;
        private int _fired;

        public HiddenSessionWindow(Action onSessionEnding)
        {
            _onSessionEnding = onSessionEnding;
            ShowInTaskbar = false;
            WindowState = FormWindowState.Minimized;
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
        }

        protected override void SetVisibleCore(bool value)
        {
            base.SetVisibleCore(false);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            WTSRegisterSessionNotification(Handle, NotIfyForThisSession);
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            WTSUnRegisterSessionNotification(Handle);
            base.OnHandleDestroyed(e);
        }

        protected override void WndProc(ref Message m)
        {
            switch (m.Msg)
            {
                case WmQueryEndSession:
                    TriggerSessionEnding();
                    m.Result = new IntPtr(1);
                    return;
                case WmEndSession when m.WParam != IntPtr.Zero:
                    TriggerSessionEnding();
                    break;
                case WmWtsSessionChange when m.WParam == new IntPtr(WtsSessionLogoff):
                    TriggerSessionEnding();
                    break;
            }

            base.WndProc(ref m);
        }

        private void TriggerSessionEnding()
        {
            if (Interlocked.Exchange(ref _fired, 1) == 1)
            {
                return;
            }

            ThreadPool.QueueUserWorkItem(_ => _onSessionEnding());
        }
    }

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSRegisterSessionNotification(IntPtr hWnd, int dwFlags);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSUnRegisterSessionNotification(IntPtr hWnd);
}
