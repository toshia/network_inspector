# -*- coding: utf-8 -*-

module Plugin::NetworkInspector
  PROPERTY_TEXT = 'Request Date(erapsed): %{start_time} (%{erapsed})
Response Code: %{code}
Rate Limit: %{ratelimit_remain}/%{ratelimit_limit} (Reset: %{ratelimit_reset})
Request Parameters:
%{param}

Response Body:
%{body}'.freeze
end
UserConfig[:network_inspector_log_max] ||= 10000
Plugin.create(:network_inspector) do

  class NetworkInspectorView < ::Gtk::CRUD
    include ::Gtk::TreeViewPrettyScroll

    gen_counter.tap do |enum|
      ICON = enum.call
      PROGRESS = enum.call
      ENDPOINT = enum.call
      START_TIME = enum.call
      ERAPSED = enum.call

      ID = enum.call
      EVENT = enum.call
    end

    def initialize(plugin)
      type_strict plugin => Plugin
      @plugin = plugin
      super()
      @creatable = @updatable = @deletable = false
      reset_activity(model)
    end

    def column_schemer
      [{kind: :pixbuf, type: Gdk::Pixbuf, label: ''},              # ICON of Service
       {kind: :text,   type: String, label: 'Progress'},           # 進捗/結果
       {kind: :text,   type: String, label: 'Endpoint'},           # エンドポイント
       {kind: :text,   type: String, label: 'Start Time'},           # 開始時間
       {kind: :text,   type: Float, label: 'Erapsed'},             # 所要時間

       {:type => Integer},                                         # ID
       {:type => Hash} ].freeze                                    # EVENT
    end

    # :network_inspector_log_max 件より古いログは消す
    def reset_activity(model)
      Reserver.new(60) {
        Delayer.new {
          if not model.destroyed?
            iters = model.to_enum(:each).to_a
            remove_count = iters.size - UserConfig[:network_inspector_log_max]
            if remove_count > 0
              iters[-remove_count, remove_count].each{ |mpi|
                model.remove(mpi[2])
              }
            end
            reset_activity(model)
          end
        }
      }
    end

    def method_missing(*args, &block)
      @plugin.__send__(*args, &block)
    end
  end

  ni_view = NetworkInspectorView.new(self)
  ni_vscrollbar = ::Gtk::VScrollbar.new(ni_view.vadjustment)
  ni_hscrollbar = ::Gtk::HScrollbar.new(ni_view.hadjustment)
  ni_shell = ::Gtk::Table.new(2, 2)
  ni_description = ::Gtk::IntelligentTextview.new
  ni_status = ::Gtk::Label.new
  ni_container = ::Gtk::VPaned.new
  ni_detail_view = Gtk::ScrolledWindow.new

  ni_detail_view.
    set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC).
    set_height_request(88)

  ni_container.
    pack1(ni_shell.
               attach(ni_view, 0, 1, 0, 1, ::Gtk::FILL|::Gtk::SHRINK|::Gtk::EXPAND, ::Gtk::FILL|::Gtk::SHRINK|::Gtk::EXPAND).
               attach(ni_vscrollbar, 1, 2, 0, 1, ::Gtk::FILL, ::Gtk::SHRINK|::Gtk::FILL).
               attach(ni_hscrollbar, 0, 1, 1, 2, ::Gtk::SHRINK|::Gtk::FILL, ::Gtk::FILL),
          true, true).
    pack2(ni_detail_view.add_with_viewport(::Gtk::VBox.new.
                                  closeup(ni_description).
                                  closeup(ni_status.right)), true, false)

  tab(:network_inspector) do
    set_icon File.join(File.dirname(__FILE__), 'icon.png')
    nativewidget Gtk::EventBox.new.add(ni_container)
  end

  ni_view.ssc("cursor-changed") { |this|
    iter = this.selection.selected
    if iter
      ni_description.rewind(iter[NetworkInspectorView::ENDPOINT])

      event = iter[NetworkInspectorView::EVENT]
      ratelimit = event[:ratelimit]
      if iter[NetworkInspectorView::EVENT][:res]
        ni_status.set_text Plugin::NetworkInspector::PROPERTY_TEXT % {
          progress: iter[NetworkInspectorView::PROGRESS],
          endpoint: iter[NetworkInspectorView::ENDPOINT],
          method: event[:method],
          param: JSON.pretty_generate(event[:options]),
          start_time: event[:start_time],
          erapsed: event[:end_time] - event[:start_time],
          ratelimit_limit: ratelimit && ratelimit.limit,
          ratelimit_remain: ratelimit && ratelimit.remain,
          ratelimit_reset: ratelimit && ratelimit.reset,

          code: event[:res].code,
          body: JSON.pretty_generate(JSON.parse(event[:res].body)) }
      else
        ni_status.set_text Plugin::NetworkInspector::PROPERTY_TEXT % {
          progress: iter[NetworkInspectorView::PROGRESS],
          endpoint: iter[NetworkInspectorView::ENDPOINT],
          method: event[:method],
          param: JSON.pretty_generate(event[:options]),
          start_time: event[:start_time],
          erapsed: Time.new - event[:start_time],
          ratelimit_limit: '(calculating)',
          ratelimit_remain: '(calculating)',
          ratelimit_reset: '(calculating)',

          code: '(calculating)',
          body: '(not yet)' } end end
    false
  }

  def icon_by_mikutwitter(mikutwitter)
    type_strict mikutwitter => MikuTwitter
    service = Service.find{ |s| s.twitter == mikutwitter }
    if service
      service.user_obj.icon end end

  progressing_iter = {}

  on_query_start do |params|
    ni_view.scroll_to_zero_lator! if ni_view.realized? and ni_view.vadjustment.value == 0.0
    iter = ni_view.model.prepend
    progressing_iter[params[:serial]] = iter
    icon = icon_by_mikutwitter(params[:mikutwitter])
    if icon
      iter[NetworkInspectorView::ICON] = icon.pixbuf(width: 24, height: 24){ |loaded_icon|
        iter[NetworkInspectorView::ICON] = loaded_icon }
    end
    iter[NetworkInspectorView::PROGRESS] = 'con.'.freeze
    iter[NetworkInspectorView::ENDPOINT] = params[:path]
    iter[NetworkInspectorView::START_TIME] = params[:start_time].to_s
    iter[NetworkInspectorView::ID] = params[:serial]
    iter[NetworkInspectorView::EVENT] = params
  end

  on_query_end do |params|
    iter = progressing_iter[params[:serial]]
    next unless iter
    code = params[:res] && params[:res].code
    iter[NetworkInspectorView::PROGRESS] = code.to_s
    iter[NetworkInspectorView::EVENT] = params
    iter[NetworkInspectorView::ERAPSED] = params[:end_time] - params[:start_time]
    progressing_iter.delete(params[:serial])
  end
end
