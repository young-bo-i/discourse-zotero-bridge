import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import AdminConfigAreaCard from "discourse/admin/components/admin-config-area-card";
import Chart from "discourse/admin/components/chart";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import DButton from "discourse/components/d-button";
import DPageSubheader from "discourse/components/d-page-subheader";
import DStatTiles from "discourse/components/d-stat-tiles";
import DateTimeInputRange from "discourse/components/date-time-input-range";
import avatar from "discourse/helpers/avatar";
import { ajax } from "discourse/lib/ajax";
import { bind } from "discourse/lib/decorators";
import { number } from "discourse/lib/formatter";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class ZoteroBridgeDashboard extends Component {
  @tracked startDate = moment().subtract(30, "days").toDate();
  @tracked endDate = new Date();
  @tracked data = this.args.model;
  @tracked selectedPeriod = "month";
  @tracked isCustomDateActive = false;
  @tracked loadingData = false;

  @tracked usersData = null;
  @tracked usersLoading = false;
  @tracked usersPage = 1;
  @tracked usersSortField = "total_requests";
  @tracked usersSortDirection = "desc";

  constructor() {
    super(...arguments);
    this.fetchUsers();
  }

  get metrics() {
    if (!this.data?.summary) {
      return [];
    }
    const s = this.data.summary;
    return [
      {
        label: i18n("zotero_bridge.admin.stats.today_requests"),
        value: s.today_requests,
      },
      {
        label: i18n("zotero_bridge.admin.stats.today_active_users"),
        value: s.today_active_users,
      },
      {
        label: i18n("zotero_bridge.admin.stats.total_requests"),
        value: s.total_requests,
      },
      {
        label: i18n("zotero_bridge.admin.stats.active_users"),
        value: s.active_users,
      },
      {
        label: i18n("zotero_bridge.admin.stats.seven_day_requests"),
        value: s.seven_day_requests,
      },
    ];
  }

  get trendChartConfig() {
    if (!this.data?.daily_trend) {
      return;
    }

    const trend = this.data.daily_trend;

    return {
      type: "bar",
      data: {
        labels: trend.map((row) => {
          return moment(row.date).format("MM-DD");
        }),
        datasets: [
          {
            label: i18n("zotero_bridge.admin.chart.requests"),
            data: trend.map((row) => row.total_requests),
            backgroundColor: "rgba(54, 162, 235, 0.6)",
            borderColor: "rgba(54, 162, 235, 1)",
            borderWidth: 1,
            yAxisID: "y",
            order: 2,
          },
          {
            label: i18n("zotero_bridge.admin.chart.active_users"),
            data: trend.map((row) => row.active_users),
            type: "line",
            borderColor: "rgba(255, 99, 132, 1)",
            backgroundColor: "rgba(255, 99, 132, 0.2)",
            borderWidth: 2,
            fill: false,
            yAxisID: "y1",
            order: 1,
          },
        ],
      },
      options: {
        responsive: true,
        interaction: {
          mode: "index",
          intersect: false,
        },
        scales: {
          y: {
            type: "linear",
            display: true,
            position: "left",
            beginAtZero: true,
            title: {
              display: true,
              text: i18n("zotero_bridge.admin.chart.requests"),
            },
          },
          y1: {
            type: "linear",
            display: true,
            position: "right",
            beginAtZero: true,
            grid: {
              drawOnChartArea: false,
            },
            title: {
              display: true,
              text: i18n("zotero_bridge.admin.chart.active_users"),
            },
          },
        },
      },
    };
  }

  get tlChartConfig() {
    if (!this.data?.trust_level_breakdown?.length) {
      return;
    }

    const breakdown = this.data.trust_level_breakdown;
    const colors = [
      "rgba(201, 203, 207, 0.7)",
      "rgba(54, 162, 235, 0.7)",
      "rgba(75, 192, 192, 0.7)",
      "rgba(255, 205, 86, 0.7)",
      "rgba(255, 99, 132, 0.7)",
    ];

    return {
      type: "doughnut",
      data: {
        labels: breakdown.map(
          (row) => `TL${row.trust_level} (${row.user_count})`
        ),
        datasets: [
          {
            data: breakdown.map((row) => row.total_requests),
            backgroundColor: breakdown.map(
              (_, idx) => colors[idx] || colors[0]
            ),
          },
        ],
      },
      options: {
        responsive: true,
        plugins: {
          legend: {
            position: "bottom",
          },
        },
      },
    };
  }

  get periodOptions() {
    return [
      { id: "day", name: i18n("zotero_bridge.admin.periods.last_day") },
      { id: "week", name: i18n("zotero_bridge.admin.periods.last_week") },
      { id: "month", name: i18n("zotero_bridge.admin.periods.last_month") },
    ];
  }

  get hasUsers() {
    return this.usersData?.users?.length > 0;
  }

  get usersTotal() {
    return this.usersData?.total_count || 0;
  }

  get usersTotalPages() {
    const perPage = this.usersData?.per_page || 20;
    return Math.ceil(this.usersTotal / perPage);
  }

  get hasNextPage() {
    return this.usersPage < this.usersTotalPages;
  }

  get hasPrevPage() {
    return this.usersPage > 1;
  }

  @action
  async fetchDashboard() {
    this.loadingData = true;
    try {
      const response = await ajax(
        "/admin/plugins/discourse-zotero-bridge/dashboard.json",
        {
          data: {
            start_date: moment(this.startDate).format("YYYY-MM-DD"),
            end_date: moment(this.endDate).format("YYYY-MM-DD"),
          },
        }
      );
      this.data = response;
    } finally {
      this.loadingData = false;
    }
    this.usersPage = 1;
    this.fetchUsers();
  }

  @action
  async fetchUsers() {
    this.usersLoading = true;
    try {
      const response = await ajax(
        "/admin/plugins/discourse-zotero-bridge/dashboard/users.json",
        {
          data: {
            start_date: moment(this.startDate).format("YYYY-MM-DD"),
            end_date: moment(this.endDate).format("YYYY-MM-DD"),
            page: this.usersPage,
            per_page: 20,
            order: this.usersSortField,
            direction: this.usersSortDirection,
          },
        }
      );
      this.usersData = response;
    } finally {
      this.usersLoading = false;
    }
  }

  @action
  setPeriodDates(period) {
    const now = moment();
    switch (period) {
      case "day":
        this.startDate = now.clone().subtract(1, "day").toDate();
        this.endDate = now.toDate();
        break;
      case "week":
        this.startDate = now.clone().subtract(7, "days").toDate();
        this.endDate = now.toDate();
        break;
      case "month":
        this.startDate = now.clone().subtract(30, "days").toDate();
        this.endDate = now.toDate();
        break;
    }
  }

  @action
  onPeriodSelect(period) {
    this.selectedPeriod = period;
    this.isCustomDateActive = false;
    this.setPeriodDates(period);
    this.fetchDashboard();
  }

  @action
  onCustomDateClick() {
    this.isCustomDateActive = !this.isCustomDateActive;
    if (this.isCustomDateActive) {
      this.selectedPeriod = null;
    }
  }

  @action
  onChangeDateRange({ from, to }) {
    this._startDate = from;
    this._endDate = to;
  }

  @action
  onRefreshDateRange() {
    this.startDate = this._startDate;
    this.endDate = this._endDate;
    this.fetchDashboard();
    this._startDate = null;
    this._endDate = null;
  }

  get fromDate() {
    return this._startDate || this.startDate;
  }

  get toDate() {
    return this._endDate || this.endDate;
  }

  @action
  sortUsers(field) {
    if (this.usersSortField === field) {
      this.usersSortDirection =
        this.usersSortDirection === "desc" ? "asc" : "desc";
    } else {
      this.usersSortField = field;
      this.usersSortDirection = "desc";
    }
    this.usersPage = 1;
    this.fetchUsers();
  }

  @action
  nextPage() {
    if (this.hasNextPage) {
      this.usersPage += 1;
      this.fetchUsers();
    }
  }

  @action
  prevPage() {
    if (this.hasPrevPage) {
      this.usersPage -= 1;
      this.fetchUsers();
    }
  }

  @bind
  sortIndicator(field) {
    if (this.usersSortField !== field) {
      return "";
    }
    return this.usersSortDirection === "asc" ? " ▲" : " ▼";
  }

  <template>
    <div class="zotero-bridge-dashboard admin-detail">
      <DPageSubheader
        @titleLabel={{i18n "zotero_bridge.admin.dashboard"}}
        @descriptionLabel={{i18n "zotero_bridge.admin.dashboard_description"}}
      />

      <div class="zotero-bridge-dashboard__filters">
        <div class="zotero-bridge-dashboard__period-buttons">
          {{#each this.periodOptions as |option|}}
            <DButton
              class={{if
                (eq this.selectedPeriod option.id)
                "btn-primary"
                "btn-default"
              }}
              @action={{fn this.onPeriodSelect option.id}}
              @translatedLabel={{option.name}}
            />
          {{/each}}
          <DButton
            class={{if this.isCustomDateActive "btn-primary" "btn-default"}}
            @action={{this.onCustomDateClick}}
            @label="zotero_bridge.admin.periods.custom"
          />
        </div>

        {{#if this.isCustomDateActive}}
          <div class="zotero-bridge-dashboard__custom-dates">
            <DateTimeInputRange
              @from={{this.fromDate}}
              @to={{this.toDate}}
              @onChange={{this.onChangeDateRange}}
              @showFromTime={{false}}
              @showToTime={{false}}
            />
            <DButton @action={{this.onRefreshDateRange}} @label="refresh" />
          </div>
        {{/if}}
      </div>

      <ConditionalLoadingSpinner @condition={{this.loadingData}}>
        <AdminConfigAreaCard
          @heading="zotero_bridge.admin.summary"
          class="zotero-bridge-dashboard__summary"
        >
          <:content>
            <DStatTiles as |tiles|>
              {{#each this.metrics as |metric|}}
                <tiles.Tile @label={{metric.label}} @value={{metric.value}} />
              {{/each}}
            </DStatTiles>
          </:content>
        </AdminConfigAreaCard>

        <div class="zotero-bridge-dashboard__charts">
          <AdminConfigAreaCard
            @heading="zotero_bridge.admin.chart.daily_trend"
            class="zotero-bridge-dashboard__trend-chart"
          >
            <:content>
              {{#if this.trendChartConfig}}
                <div class="zotero-bridge-dashboard__chart-container">
                  <Chart
                    @chartConfig={{this.trendChartConfig}}
                    class="zotero-bridge-dashboard__chart"
                  />
                </div>
              {{/if}}
            </:content>
          </AdminConfigAreaCard>

          <AdminConfigAreaCard
            @heading="zotero_bridge.admin.chart.tl_breakdown"
            class="zotero-bridge-dashboard__tl-chart"
          >
            <:content>
              {{#if this.tlChartConfig}}
                <div class="zotero-bridge-dashboard__chart-container --doughnut">
                  <Chart
                    @chartConfig={{this.tlChartConfig}}
                    class="zotero-bridge-dashboard__chart"
                  />
                </div>
              {{/if}}
            </:content>
          </AdminConfigAreaCard>
        </div>

        <AdminConfigAreaCard
          @heading="zotero_bridge.admin.users_table.title"
          class="zotero-bridge-dashboard__users"
        >
          <:content>
            <ConditionalLoadingSpinner @condition={{this.usersLoading}}>
              {{#if this.hasUsers}}
                <table class="zotero-bridge-dashboard__users-table">
                  <thead>
                    <tr>
                      <th>
                        <DButton
                          class="btn-transparent"
                          @action={{fn this.sortUsers "username"}}
                          @translatedLabel="{{i18n
                            'zotero_bridge.admin.users_table.username'
                          }}{{this.sortIndicator 'username'}}"
                        />
                      </th>
                      <th>
                        <DButton
                          class="btn-transparent"
                          @action={{fn this.sortUsers "trust_level"}}
                          @translatedLabel="{{i18n
                            'zotero_bridge.admin.users_table.trust_level'
                          }}{{this.sortIndicator 'trust_level'}}"
                        />
                      </th>
                      <th>
                        <DButton
                          class="btn-transparent"
                          @action={{fn this.sortUsers "total_requests"}}
                          @translatedLabel="{{i18n
                            'zotero_bridge.admin.users_table.total_requests'
                          }}{{this.sortIndicator 'total_requests'}}"
                        />
                      </th>
                      <th>
                        <DButton
                          class="btn-transparent"
                          @action={{fn this.sortUsers "extra_requests"}}
                          @translatedLabel="{{i18n
                            'zotero_bridge.admin.users_table.extra_requests'
                          }}{{this.sortIndicator 'extra_requests'}}"
                        />
                      </th>
                      <th>
                        <DButton
                          class="btn-transparent"
                          @action={{fn this.sortUsers "last_active_on"}}
                          @translatedLabel="{{i18n
                            'zotero_bridge.admin.users_table.last_active'
                          }}{{this.sortIndicator 'last_active_on'}}"
                        />
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {{#each this.usersData.users as |user|}}
                      <tr>
                        <td class="zotero-bridge-dashboard__user-cell">
                          <a
                            href="/admin/users/{{user.id}}/{{user.username}}"
                            class="zotero-bridge-dashboard__user-link"
                          >
                            {{avatar
                              user
                              imageSize="tiny"
                              extraClasses="zotero-bridge-dashboard__avatar"
                            }}
                            {{user.username}}
                          </a>
                        </td>
                        <td>TL{{user.trust_level}}</td>
                        <td title={{user.total_requests}}>{{number
                            user.total_requests
                          }}</td>
                        <td>{{user.extra_requests}}</td>
                        <td>{{user.last_active_on}}</td>
                      </tr>
                    {{/each}}
                  </tbody>
                </table>

                <div class="zotero-bridge-dashboard__pagination">
                  <DButton
                    class="btn-default"
                    @action={{this.prevPage}}
                    @disabled={{(if this.hasPrevPage false true)}}
                    @label="zotero_bridge.admin.pagination.prev"
                  />
                  <span class="zotero-bridge-dashboard__page-info">
                    {{i18n
                      "zotero_bridge.admin.pagination.page_info"
                      current=this.usersPage
                      total=this.usersTotalPages
                    }}
                  </span>
                  <DButton
                    class="btn-default"
                    @action={{this.nextPage}}
                    @disabled={{(if this.hasNextPage false true)}}
                    @label="zotero_bridge.admin.pagination.next"
                  />
                </div>
              {{else}}
                <p class="zotero-bridge-dashboard__no-data">
                  {{i18n "zotero_bridge.admin.users_table.no_data"}}
                </p>
              {{/if}}
            </ConditionalLoadingSpinner>
          </:content>
        </AdminConfigAreaCard>
      </ConditionalLoadingSpinner>
    </div>
  </template>
}
