//  
//  Copyright (C) 2011 Robert Dyer, Rico Tzschichholz
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Gdk;
using Gtk;

using Plank.Drawing;
using Plank.Services;
using Plank.Services.Windows;

namespace Plank.Items
{
	public class ApplicationDockItem : DockItem
	{
		public signal void app_closed ();
		
		public Bamf.Application? App { get; private set; }
		
		protected ApplicationDockItem ()
		{
		}
		
		~ApplicationDockItem ()
		{
			set_app (null);
			stop_monitor ();
		}
		
		public ApplicationDockItem.with_dockitem (string dockitem)
		{
			Prefs = new DockItemPreferences.with_file (dockitem);
			if (!ValidItem)
				return;
			
			Prefs.notify["Launcher"].connect (() => {
				update_app ();
				launcher_changed ();
			});
			
			load_from_launcher ();
			start_monitor ();
		}
		
		public void set_app (Bamf.Application? app)
		{
			if (App != null) {
				App.active_changed.disconnect (update_active);
				App.urgent_changed.disconnect (update_urgent);
				App.child_added.disconnect (update_indicator);
				App.child_removed.disconnect (update_indicator);
				App.closed.disconnect (signal_app_closed);
			}
			
			App = app;
			
			update_states ();
			
			if (app != null) {
				app.active_changed.connect (update_active);
				app.urgent_changed.connect (update_urgent);
				app.child_added.connect (update_indicator);
				app.child_removed.connect (update_indicator);
				app.closed.connect (signal_app_closed);
			}
		}
		
		public void signal_app_closed ()
		{
			app_closed ();
		}
		
		protected bool is_window ()
		{
			return (App != null && App.get_desktop_file () == "");
		}
		
		public void update_app ()
		{
			set_app (Matcher.get_default ().app_for_launcher (Prefs.Launcher));
		}
		
		public void update_urgent (bool is_urgent)
		{
			var was_urgent = (State & ItemState.URGENT) == ItemState.URGENT;
			
			if (is_urgent && !was_urgent) {
				LastUrgent = new DateTime.now_utc ();
				State |= ItemState.URGENT;
			} else if (!is_urgent && was_urgent) {
				State &= ~ItemState.URGENT;
			}
		}
		
		public void update_indicator ()
		{
			if (App == null || App.is_closed () || !App.is_running ()) {
				if (Indicator != IndicatorState.NONE)
					Indicator = IndicatorState.NONE;
			} else if (WindowControl.get_num_windows (App) > 1) {
				if (Indicator != IndicatorState.SINGLE_PLUS)
					Indicator = IndicatorState.SINGLE_PLUS;
			} else {
				if (Indicator != IndicatorState.SINGLE)
					Indicator = IndicatorState.SINGLE;
			}
		}
		
		public void update_active (bool is_active)
		{
			var was_active = (State & ItemState.ACTIVE) == ItemState.ACTIVE;
			
			// set active
			if (is_active && !was_active) {
				LastActive = new DateTime.now_utc ();
				State |= ItemState.ACTIVE;
			} else if (!is_active && was_active) {
				LastActive = new DateTime.now_utc ();
				State &= ~ItemState.ACTIVE;
			}
		}
		
		public void update_states ()
		{
			if (App == null || App.is_closed () || !App.is_running ()) {
				update_urgent (false);
				update_active (false);
			} else {
				update_urgent (App.is_urgent ());
				update_active (App.is_active ());
			}
			update_indicator ();
		}
		
		public override void launch ()
		{
			Services.System.launch (File.new_for_path (Prefs.Launcher), {});
		}
		
		protected override ClickAnimation on_clicked (uint button, ModifierType mod)
		{
			if (((App == null || App.get_children ().length () == 0) && button == 1) ||
				button == 2 || 
				(button == 1 && (mod & ModifierType.CONTROL_MASK) == ModifierType.CONTROL_MASK)) {
				launch ();
				return ClickAnimation.BOUNCE;
			}
			
			if ((App == null || App.get_children ().length () == 0) || button != 1)
				return ClickAnimation.NONE;
			
			WindowControl.smart_focus (App);
			
			return ClickAnimation.DARKEN;
		}
		
		protected override void on_scrolled (ScrollDirection direction, ModifierType mod)
		{
			if (WindowControl.get_num_windows (App) == 0 ||
				(new DateTime.now_utc ().difference (LastScrolled) < SCROLL_RATE))
				return;
			
			LastScrolled = new DateTime.now_utc ();
			
			if ((direction & ScrollDirection.UP) == ScrollDirection.UP ||
				(direction & ScrollDirection.LEFT) == ScrollDirection.LEFT)
				WindowControl.focus_previous (App);
			else
				WindowControl.focus_next (App);
		}
		
		public override List<MenuItem> get_menu_items ()
		{
			List<MenuItem> items = new List<MenuItem> ();
			
			if (App == null || App.get_children ().length () == 0) {
				var item = new ImageMenuItem.from_stock (STOCK_OPEN, null);
				item.activate.connect (() => launch ());
				items.append (item);
			} else {
				MenuItem item;
				
				if (!is_window ()) {
					item = add_menu_item (items, _("_Open New Window"), "document-open-symbolic;;document-open");
					item.activate.connect (() => launch ());
					items.append (item);
				}
				
				if (WindowControl.has_maximized_window (App)) {
					item = add_menu_item (items, _("Unma_ximize"), "view-fullscreen");
					item.activate.connect (() => WindowControl.unmaximize (App));
					items.append (item);
				} else {
					item = add_menu_item (items, _("Ma_ximize"), "view-fullscreen");
					item.activate.connect (() => WindowControl.maximize (App));
					items.append (item);
				}
				
				if (WindowControl.has_minimized_window (App)) {
					item = add_menu_item (items, _("_Restore"), "view-restore");
					item.activate.connect (() => WindowControl.restore (App));
					items.append (item);
				} else {
					item = add_menu_item (items, _("Mi_nimize"), "view-restore");
					item.activate.connect (() => WindowControl.minimize (App));
					items.append (item);
				}
				
				item = add_menu_item (items, _("_Close All"), "window-close-symbolic;;window-close");
				item.activate.connect (() => WindowControl.close_all (App));
				items.append (item);
				
				List<Bamf.Window> windows = WindowControl.get_windows (App);
				if (windows.length () > 0) {
					items.append (new SeparatorMenuItem ());
					
					int width, height;
					icon_size_lookup (IconSize.MENU, out width, out height);
					
					for (int i = 0; i < windows.length (); i++) {
						var window = windows.nth_data (i);
						
						var pbuf = WindowControl.get_window_icon (window);
						if (pbuf == null)
							DrawingService.load_icon (Icon, width, height);
						else
							pbuf = DrawingService.ar_scale (pbuf, width, height);
						
						var window_item = new ImageMenuItem.with_mnemonic (window.get_name ());
						window_item.set_image (new Gtk.Image.from_pixbuf (pbuf));
						window_item.activate.connect (() => WindowControl.focus_window (window));
						items.append (window_item);
					}
				}
			}
			
			return items;
		}
		
		protected FileMonitor monitor;
		
		protected void start_monitor ()
		{
			if (monitor != null)
				return;
			
			try {
				monitor = File.new_for_path (Prefs.Launcher).monitor (0);
				monitor.set_rate_limit (500);
				monitor.changed.connect (monitor_changed);
			} catch {
				Logger.warn<ApplicationDockItem> ("Unable to watch the launcher file '%s'".printf (Prefs.Launcher));
			}
		}
		
		protected void monitor_changed (File f, File? other, FileMonitorEvent event)
		{
			if ((event & FileMonitorEvent.CHANGES_DONE_HINT) == 0 &&
				(event & FileMonitorEvent.DELETED) == 0)
				return;
			
			Logger.debug<ApplicationDockItem> ("Launcher file '%s' changed, reloading".printf (Prefs.Launcher));
			load_from_launcher ();
		}
		
		protected void stop_monitor ()
		{
			if (monitor == null)
				return;
			
			monitor.cancel ();
			monitor = null;
		}
		
		protected void load_from_launcher ()
		{
			//TODO use the information from Bamf.Application which should give us a localized app-name
			string icon, text;
			parse_launcher (Prefs.Launcher, out icon, out text);
			Icon = icon;
			Text = text;
		}
		
		public static void parse_launcher (string launcher, out string icon, out string text)
		{
			try {
				KeyFile file = new KeyFile ();
				file.load_from_file (launcher, 0);
				
				icon = file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
				text = file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME);
			} catch {
				icon = "";
				text = "";
			}
		}
	}
}
